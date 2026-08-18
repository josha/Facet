--!strict
--[[ shrink — the MAIN-AXIS SHRINK PASS and its degrade cascade.

	Public interface: `shrink.stack(deps, ctx, children, isH, basisMain, deficit,
	shrunk) -> (absorbed, priorityOrder?)`, plus `shrink.EMPTY`, the frozen
	"nothing shrank" result table. Depends on `./text_metrics` and on three
	functions the solver injects (`Deps`, below).

	WHY IT IS ITS OWN FILE. `src/layout/solver.luau` crossed the 200,000-character
	`Script.Source` write cap on 2026-08-14 and stopped live-syncing into an open
	Studio session, silently — so a live check against it tested the built place
	instead of the edits (tools/check_source_size.py). The seam was chosen by the
	test that decides every split in this library: does the block read or WRITE a
	mutable upvalue of the file it is leaving?

	THIS BLOCK WROTE ONE, and lifting it out is what makes that upvalue go away.
	`shrinkStack` was a FORWARD DECLARATION — `local shrinkStack: (...) -> (...)`
	near the top of the solver, assigned ~2,300 lines later — because both passes
	run it and the measure branch's PASS 1.5 calls it long before the arrange
	helpers are defined. A forward-declared local assigned far from its
	declaration is precisely the shape
	`docs/lessons/later-locals-are-not-upvalues.md` records, and the solver had
	four of them. It now has three: this one is a require, bound before anything
	can call it.

	THE THREE THINGS IT NEEDS FROM THE SOLVER are pure, immutable module-level
	functions there, so they arrive as an explicit `Deps` record rather than
	through a shared mutable binding: `mainDimOf` (the main-axis dimension,
	Spacer's `fill` default included), `sides` (the padding/margin quadruple), and
	`textTypography` (the ONE resolution of a text node's face and size — a second
	copy of that role ladder is exactly how a floor ends up computed at `body` for
	a label drawn at `caption`). They are threaded as an argument rather than
	captured at load, so this module holds no state and two solves can never see
	different ones.

	MEASURE AND ARRANGE STILL READ THE SAME CODE, which is the whole constraint on
	touching this file: the recurring defect class here is "a container that
	measured one shape and arranged another", fixed four separate times. Both
	callers call this one function; there is no second copy and no per-pass branch.
]]

local text_metrics = require("./text_metrics")

local shrink = {}

-- What the pass needs from the solver, passed at every call. Typed `any` for the
-- node/ctx arguments on purpose: the solver requires THIS module, so importing
-- `solver.Node`/`Ctx` back would be a require cycle, and re-declaring either
-- schema here is the copy-goes-stale failure this seam exists to avoid.
export type Deps = {
	mainDimOf: (child: any, isH: boolean) -> any,
	sides: (margin: any) -> (number, number, number, number),
	textTypography: (ctx: any, node: any) -> (string, number, number),
}

--[[ ===== THE SHRINK PASS (docs/plans/swiftui-parity-round2.md §2.4) ==========

	UNTIL THIS, THE SOLVER HAD NO SHRINK PASS AT ALL. `remaining = math.max(0,
	availMain)` clamped the deficit away: `hug`/`content`/`fixed` children kept
	their full desired extent, the cursor kept advancing, and the row painted past
	its own box with only the overflow diagnostic to say so.

	TWO INPUTS, TWO LEVELS OF ONE ALGORITHM. `layoutPriority` (default 0) is the
	OUTER sort — tiers, consumed lowest-first, which is SwiftUI's model.
	`shrinkWeight` (default 0) is the INNER distribution — inside a tier the deficit
	is split proportionally to `shrinkWeight x basis`, which is CSS's. Ordering
	alone was not enough and the hole was on the DEFAULT path: with every child at
	priority 0 they all sit in one tier, and "ascending priority order" says nothing
	about what happens inside one — left to document order the first of three equal
	overflowing chips would collapse to its floor while its two siblings stayed full
	size.

	`shrinkWeight = 0` MEANS NEVER, and it is the default, so today's geometry is
	preserved exactly and no shipped screen moves. That is also the native-parity
	choice: Roblox's `Enum.UIFlexMode.None` is likewise the default and likewise
	documented "neither shrinks nor grows". `shrinkWeight = 1` is `UIFlexMode.Shrink`
	/ CSS `flex-shrink: 1`.

	TWO DETAILS ROBLOX'S DOCS LEAVE UNDEFINED, decided here and owned as Facet's
	own rulings rather than claimed as parity:

	  * the weight is MULTIPLIED BY THE BASIS, as CSS does. Without it a 400px child
	    and a 40px child give up the same pixels, which collapses the small one
	    first;
	  * the FLOOR STACK is `minMax.min` -> a text node's min-content width (its
	    longest word — squeezed under that the engine breaks the word rather than
	    clipping a pixel) -> `0`, in that order.

	WHERE IT RUNS, AND WHERE IT CANNOT. A deficit exists wherever the space a stack
	has is smaller than the space its children want, and a stack learns that twice:
	from the OFFER the measure pass hands it, and from the RECT arrange hands it. So
	the pass runs in both — the measure branch's PASS 1.5 and arrange's own block —
	and in both the shrunk children are re-measured at their reduced offer, because
	a squeezed label would otherwise keep the box of a wrap it is not going to get.

	It cannot fire under a `hug`/`content` parent, which offers its children exactly
	what it measured: there is no deficit to absorb, and nothing shrinks. That is not
	a limitation, it is the definition of hugging.

	Shipping the arrange half alone (2026-08-12, for one day) left the two passes
	disagreeing: measure reserved the CROSS extent of an unsqueezed label and arrange
	then squeezed it onto eight lines, which painted seven of them outside the row.
	The measure-side mirror is what closed that, and it is the same repair the `fill`
	child's second measure pass already was. Both re-measures also keep the measure
	memo honest: the pass only ever varies the OFFER, which `maxW`/`maxH` already key
	— verified for each caller separately under a `ScrollView`, where the memo is
	live (tests/stack_distribution.spec.luau).
]]

--[[ ===== THE DEGRADE CASCADE (director ruling 1, 2026-08-13) ==================

	MEASURED DEFECT: three `shrinkWeight = 1` texts in a 120px box solved to
	`x0 w120 / x120 w120 / x240 w100` — two landed WHOLLY OUTSIDE the box, because
	`absorbTier` can absorb at most `Sum(basis - floor)` and the residual deficit
	was simply not absorbed. Director's ruling, verbatim: *"clip is ok; should we
	switch to compact and then truncate the text before clipping (with '...')?"*

	So the answer is a CASCADE, and each rung only happens when the one above it
	still does not fit:

	  1. COMPACT — a node that declared a compact representation gives that up
	     before it gives up any of its string. (The floor drops to the compact
	     form's own min-content; the re-measure at the reduced offer is what makes
	     the compact ladder actually choose it, so there is no second mechanism.)
	  2. TRUNCATE — the text is allowed below its longest word, down to the width
	     of an ellipsis. Below min-content the string cannot wrap, so the wrap rule
	     above measures it on ONE line and the engine's TextTruncate.AtEnd cuts it
	     with a `…`: the text tells the truth about being cut.
	  3. CLIP — the floor guarantee, applied in the arrange loop below: whatever
	     the cascade could not absorb is cropped at the box edge, so nothing EVER
	     paints outside its parent. Last resort, never the first move.

	AN AUTHORED `minMax.min` IS NOT A RUNG. It is a contract ("never below this"),
	so it wins at every rung; only the floor the framework DERIVED from the text
	gives way. That is also what keeps the cascade from silently undoing a
	deliberate minimum.

	The rungs are re-run from the ORIGINAL basis rather than stacked, so `absorbed`
	is always the whole answer for the rung that produced it and a lower floor can
	only ever absorb more (floors are monotonically non-increasing down the ladder).
]]
local FLOOR_NATURAL = 1 -- today's: an authored min, else the longest word
local FLOOR_COMPACT = 2 -- ...else the compact form's longest word
local FLOOR_TRUNCATE = 3 -- ...else one ellipsis
-- U+2026. The narrowest honest thing a cut label can still say; the engine draws
-- exactly this character when TextTruncate.AtEnd engages.
local ELLIPSIS = "\u{2026}"

-- The narrowest main extent this child may be squeezed to AT `rung`. Never above
-- `basis`: a floor larger than the natural size would mean "shrinking" a child
-- upwards.
local function shrinkFloorOf(deps: Deps, ctx: any, child: any, isH: boolean, basis: number, rung: number): number
	local d = deps.mainDimOf(child, isH)
	if d.type == "minMax" and type(d.min) == "number" then
		-- an AUTHORED minimum is a contract, not a rung (see the block above)
		return math.min(d.min :: number, basis)
	end
	-- min-content applies to a text node's WIDTH; a vertical stack squeezing a
	-- label's HEIGHT has no equivalent (there is no "minimum wrap height"), so the
	-- floor there is whatever `minMax.min` declared, else 0.
	if isH and child.kind == "text" then
		local font, size = deps.textTypography(ctx, child)
		local _, pr, _, pl = deps.sides(child.padding)
		if rung >= FLOOR_TRUNCATE then
			return math.min(text_metrics.minWidth(ELLIPSIS, font, size) + pl + pr, basis)
		end
		-- the string this node will actually DRAW — the compact ladder's verdict is
		-- published on `ctx.compact` by the measure that reserved the box, and the
		-- floor has to belong to the same string. At `FLOOR_COMPACT` the ladder has
		-- not chosen the compact form yet (this offer is still the unsqueezed one),
		-- so the floor is the one the re-measure at the reduced offer WILL produce.
		local drawn = if child.compactText ~= nil and (rung >= FLOOR_COMPACT or ctx.compact[child.id] == true)
			then child.compactText :: string
			else (child.text or "")
		return math.min(text_metrics.minWidth(drawn, font, size) + pl + pr, basis)
	end
	return 0
end

type ShrinkMember = { idx: number, basis: number, floor: number, scaled: number, priority: number }

-- the "nothing shrank" reading of the per-child result table, shared and frozen so
-- the overwhelmingly common arrange (no deficit, or no child that opted in) costs
-- one assignment rather than one table
shrink.EMPTY = (table.freeze({}) :: any) :: { [number]: number }

-- Absorb what one PRIORITY TIER (members[lo..hi]) can of `deficit`, writing each
-- member's new main extent into `shrunk`. Returns the pixels actually absorbed.
local function absorbTier(
	members: { ShrinkMember },
	lo: number,
	hi: number,
	deficit: number,
	shrunk: { [number]: number }
): number
	local cap = 0
	for k = lo, hi do
		cap += members[k].basis - members[k].floor
	end
	if cap <= 0 then
		return 0
	end
	-- integer pixels, and CEIL rather than floor: under-absorbing by a fraction
	-- would leave `availMain` at -0.4 and re-fire the overflow diagnostic on a row
	-- that visibly fits
	local want = math.min(math.ceil(deficit), cap)
	if want <= 0 then
		return 0
	end
	if want >= cap then
		for k = lo, hi do
			shrunk[members[k].idx] = members[k].floor
		end
		return cap
	end
	-- Proportional-with-freezing, CSS's resolution loop: a member whose share would
	-- take it under its floor is frozen AT the floor and the rest is redistributed
	-- over the others, because handing it out in one pass is how a floored child
	-- silently keeps a share nobody else could use.
	local frozen: { [number]: boolean } = {}
	local take: { [number]: number } = {}
	local left = want
	while true do
		local total = 0
		for k = lo, hi do
			if not frozen[k] then
				total += members[k].scaled
			end
		end
		if total <= 0 then
			break
		end
		local froze = false
		for k = lo, hi do
			if not frozen[k] then
				local room = members[k].basis - members[k].floor
				if left * members[k].scaled / total >= room then
					frozen[k] = true
					take[k] = room
					left -= room
					froze = true
				end
			end
		end
		if not froze then
			for k = lo, hi do
				if not frozen[k] then
					take[k] = left * members[k].scaled / total
				end
			end
			break
		end
	end
	-- largest-remainder rounding, the same rule (and the same tie-break) the `fill`
	-- distribution below uses, so the tier absorbs exactly `want` whole pixels
	local acc = 0
	local order: { { k: number, rem: number } } = {}
	for k = lo, hi do
		local exact = take[k] or 0
		local floored = math.floor(exact)
		take[k] = floored
		acc += floored
		table.insert(order, { k = k, rem = exact - floored })
	end
	table.sort(order, function(a, b)
		return if a.rem ~= b.rem then a.rem > b.rem else a.k < b.k
	end)
	local spare = want - acc
	for _, entry in order do
		if spare <= 0 then
			break
		end
		local m = members[entry.k]
		if (take[entry.k] or 0) + 1 <= m.basis - m.floor then
			take[entry.k] = (take[entry.k] or 0) + 1
			spare -= 1
		end
	end
	local absorbed = 0
	for k = lo, hi do
		local amount = take[k] or 0
		if amount > 0 then
			shrunk[members[k].idx] = members[k].basis - amount
			absorbed += amount
		end
	end
	return absorbed
end

-- Run the whole pass over one stack's children. Returns (absorbed, priorityOrder)
-- where `priorityOrder` is nil when NOTHING opted in — which is what keeps the
-- overflow diagnostic's historic wording byte-identical on the default path.
--
-- TWO CALLERS, ONE ALGORITHM (say which path a comment describes —
-- docs/lessons/a-header-comment-describes-the-path-it-was-written-for.md):
--
--   * MEASURE, at PASS 1.5 of the stack branch, when the offer this stack was
--     handed is already too small for its children. It uses the answer to re-
--     measure the squeezed children and report the CROSS extent they will really
--     need, and it throws the priority order away — nothing diagnoses at measure
--     time.
--   * ARRANGE, against the real box, which is where the rects are decided and
--     where the overflow diagnostic's priority suffix comes from.
--
-- `basisMain` is the natural MAIN extent per child index, margins excluded — the
-- number each caller already has (measure keeps it as a bare number, arrange has
-- it inside its `desired` sizes). An index missing from it is a child this pass
-- must not touch: at measure that is a `fill` child (no basis of its own) or one
-- that never opted in; at arrange it is a `fill` child, which the clamp that
-- produced this deficit already handed zero.
function shrink.stack(
	deps: Deps,
	ctx: any,
	children: { any },
	isH: boolean,
	basisMain: { [number]: number },
	deficit: number,
	shrunk: { [number]: number }
): (number, string?)
	local members: { ShrinkMember } = {}
	for idx, child in children do
		local weight = child.shrinkWeight
		if
			type(weight) == "number"
			and weight > 0
			and basisMain[idx] ~= nil
			and deps.mainDimOf(child, isH).type ~= "fill"
		then
			local basis = basisMain[idx]
			if basis > 0 then
				table.insert(members, {
					idx = idx,
					basis = basis,
					floor = shrinkFloorOf(deps, ctx, child, isH, basis, FLOOR_NATURAL),
					scaled = weight * basis,
					priority = child.layoutPriority or 0,
				})
			end
		end
	end
	if #members == 0 then
		return 0, nil
	end
	table.sort(members, function(a, b)
		return if a.priority ~= b.priority then a.priority < b.priority else a.idx < b.idx
	end)
	-- ONE PASS OVER THE PRIORITY TIERS, at whatever floors `members` currently
	-- carries. The cascade below re-runs it with lower floors; each run starts from
	-- the ORIGINAL basis, so its answer is the whole answer for that rung.
	local tiers: { string } = {}
	local function runTiers(): number
		local absorbed = 0
		local i = 1
		local tier = 0
		while i <= #members do
			local j = i
			while j < #members and members[j + 1].priority == members[i].priority do
				j += 1
			end
			tier += 1
			if #tiers < tier then
				table.insert(tiers, tostring(members[i].priority))
			end
			if deficit - absorbed > 0 then
				absorbed += absorbTier(members, i, j, deficit - absorbed, shrunk)
			end
			i = j + 1
		end
		return absorbed
	end
	local function capOf(): number
		local cap = 0
		for _, m in members do
			cap += m.basis - m.floor
		end
		return cap
	end
	local cap = capOf()
	local absorbed = runTiers()
	-- THE DEGRADE CASCADE (director ruling 1 — the block comment above
	-- `shrinkFloorOf` states it). Only while a deficit is left, and only when the
	-- next rung actually buys room: a row of boxes has the same floor at every
	-- rung, so it pays one arithmetic sweep and never a second tier walk.
	local rung = FLOOR_NATURAL
	while absorbed < deficit and rung < FLOOR_TRUNCATE do
		rung += 1
		for _, m in members do
			local floor = shrinkFloorOf(deps, ctx, children[m.idx], isH, m.basis, rung)
			if floor < m.floor then
				m.floor = floor
			end
		end
		local nextCap = capOf()
		if nextCap > cap then
			cap = nextCap
			-- the previous rung's answer is SUPERSEDED, never added to: every rung
			-- shrinks from the original basis
			table.clear(shrunk)
			absorbed = runTiers()
		end
	end
	return absorbed, table.concat(tiers, ", ")
end

return shrink
