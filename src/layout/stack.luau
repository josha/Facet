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
	the reason `grid.luau`'s header states about its own pair: both are declared
	BELOW the line the Deps record is built on, so a by-value capture there would
	take the nil global, and forward-declaring them to avoid that would add a mutable
	module local, which is the opposite of what a split is for.

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
local placementLib = require("./placement")
-- bound at module scope for the reason `grid.luau` records: a per-call lookup on
-- the arrange hot loop is a bench regression this repository has already paid for
local roundPx = num.roundPx
local alignOffset = placementLib.alignOffset
local distributionOf = placementLib.distributionOf

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
) -> ()

-- a solved box, declared here rather than imported for the reason the `Deps` note
-- above gives: `./anchor_placement`, `./composition` and `./text_audit` each
-- declare the same four numbers for the same reason.
export type Rect = { x: number, y: number, w: number, h: number }

-- vstack / hstack. Main axis, in order: fixed/content children keep their
-- desired size unless they declared a `shrinkWeight` and the axis is SHORT (the
-- shrink pass, §2.4); `fill` children then share any surplus by weight
-- (largest-remainder rounding); and `distribute` spreads what fill did not take
-- (§2.6). Cross axis honours `child.lineAlign`, else `child.align`, else this
-- container's `align` (`stretch` fills the line).
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
		local w, h = deps.measure(ctx, child, innerW, innerH)
		desired[idx] = { w = w, h = h }
		if mainDim.type == "fill" then
			fillWeightSum += mainDim.weight or 1
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
		table.insert(ctx.diagnostics, { node = node.id, issue = issue })
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
			fillPx[share.i] = share.floor + (if rank <= leftover then 1 else 0)
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
				table.insert(ctx.diagnostics, {
					node = node.id,
					issue = string.format(
						'distribute = "%s" has nothing to distribute on this %s: a `fill` child already takes '
							.. 'the whole leftover (drop the fill dimension, or leave distribute at "start")',
						mode,
						node.kind
					),
				})
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
			local y = innerY + m.t + alignOffset(childAlign, crossAvail, crossSize)
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
		noteContainment(ctx, node, child, childRect, innerX, innerY, innerW, innerH, not isH)
		place(ctx, child, childRect, out)
	end
end

return stack
