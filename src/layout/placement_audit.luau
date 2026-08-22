--!strict
--[[ placement_audit — the PARENT-side policing of the nine placement props.

	WHAT IT IS. `anchor`, `offsetX`, `offsetY`, `alignH`, `alignV`, `lineAlign`,
	`gridSpan`, `layoutPriority` and `shrinkWeight` are legal on every node but
	read only by particular parent arrange branches. This module holds the table
	of which parent kind reads which prop, the advice for every (kind, prop) pair
	that is inert, and `auditPlacement` — the walk that turns the pair into a
	diagnostic. Public interface: `auditPlacement(parentKind, parentId, children)`
	-> findings or nil. Depends on nothing (no require, no solver state).

	WHY IT IS ITS OWN FILE, since the block below used to say "IT LIVES HERE, next
	to the branches". `src/layout/solver.luau` crossed the 200,000-character
	`Script.Source` write cap on 2026-08-14 and stopped live-syncing into an open
	Studio session, silently — so a live check against it tested the built place
	instead of the edits (tools/check_source_size.py). The seam was chosen by the
	test that decides every split in this library: does the block read or write a
	mutable upvalue of the file it is leaving? This one reads NOTHING from the
	solve — no `ctx`, no `measure`, no `arrange` local, no forward declaration —
	so it left without taking an argument with it, and the two passes it describes
	cannot drift from it because it is not part of either.

	IT IS STILL THE SOLVER'S STATEMENT, and that is the part of the old comment
	that has not changed: it says what `solver.luau`'s arrange branches do, it
	sits beside them (same directory, one require away), and it must never be
	copied next to its READER. `renderer.toLayoutNode` calls it and reports the
	findings on `Node.inertPlacement`; a copy over there would go stale the first
	time a branch learns a new prop. Re-exported as `solver.auditPlacement`, which
	is the name every caller and every doc uses.
]]

local placement_audit = {}

-- ONE node of the layout snapshot, as this audit reads it: `kind`, `id`,
-- `placementProps`, and the nine props by name. Typed `any` rather than
-- `solver.Node` on purpose — the solver requires THIS module, so importing its
-- type back would be a require cycle, and re-declaring that 180-line schema here
-- is exactly the copy-goes-stale failure the header warns about.
-- ===== THE PLACEMENT-PROP READ TABLE (parity round 2 §2.1) ==================
--
-- `anchor`, `offsetX`, `offsetY`, `alignH`, `alignV`, `lineAlign`, `gridSpan`,
-- `layoutPriority` and `shrinkWeight` are shared BOX props — legal on EVERY node
-- — but not one of them is a fact the node has of its own. Each is a placement
-- instruction addressed to a particular kind of PARENT, and every arrange branch
-- below reads only the ones it knows: an `anchor` branch reads
-- `anchor`/`offsetX`/`offsetY`, a `zstack` reads `alignH`/`alignV`, a stack reads
-- `lineAlign` and the shrink pair, a `gridrow` reads `gridSpan`.
--
-- THE SHRINK PAIR JOINED LATE, and that is a finding rather than a design (the
-- Milestone-1 architecture review, C2). `layoutPriority`/`shrinkWeight` shipped in
-- the same parity round as this table, declared in the schema paragraph that names
-- the five audited props beside them — and were left out of it. Only a
-- `vstack`/`hstack` shrink pass reads either one, so `UI.Text{ shrinkWeight = 2 }`
-- under a ZStack, a Grid, an Anchor or a ScrollView was accepted and did nothing,
-- with no diagnostic: the exact §4 violation this table was built to eliminate,
-- re-committed by the mission that built it.
--
-- Anywhere else the prop is ACCEPTED AND THEN IGNORED, which is exactly what
-- constitution §4 forbids ("a property that is accepted must do something"). The
-- child cannot catch it — a child does not know its parent at its own
-- construction — so the parent catches it, and this table is what it checks
-- against.
--
-- IT LIVES HERE, next to the branches, and not next to the reader: it is a
-- statement about what THIS file's arrange does, and a copy kept anywhere else
-- goes stale the first time a branch learns a new prop. `renderer.toLayoutNode`
-- consults it; the audit's findings ride back in on `Node.inertPlacement`.
--
-- TWO SUBTLETIES, both of which a naive table gets wrong:
--
-- 1. `alignH`/`alignV` are ALSO container props. A zstack reads its own
--    (`child.alignH or node.alignH`, below) as the default for its children, so
--    a `UI.ZStack{ alignH = "end" }` under an hstack is doing real work and must
--    never be flagged. That is the `SELF_READ` set.
-- 2. TWO CELLS ARE CLOSED BY THE SCHEMA and therefore have no case here, because
--    a branch that cannot be reached cannot be tested and cannot be trusted:
--      * a ROW-MODE grid's children are `UI.GridRow`s, whose prop set
--        (`blueprint_schema.luau` class "GridRow") admits paint and nothing else;
--      * a `UI.Composition`'s children are `UI.Region`s — it refuses any child
--        that is not one — and a Region's prop set is just as closed
--        (`floor`/`group`/`mayDrop`/`mayScroll`/`rank`/`reserved`/`sizing`/
--        `weight`).
--    In both, every placement prop is already a CONSTRUCTION error, which is the
--    louder answer anyway. `tests/placement_audit.spec.luau` pins both schemas so
--    that loosening either one goes red here rather than silently unpolicing a
--    parent kind. A `region`'s own chosen FORM is an ordinary box, so `region`
--    below is reachable and does have a case.
local PLACEMENT_PROPS =
	{ "anchor", "offsetX", "offsetY", "alignH", "alignV", "lineAlign", "gridSpan", "layoutPriority", "shrinkWeight" }
local PLACEMENT_READS: { [string]: { [string]: boolean } } = {
	anchor = { anchor = true, offsetX = true, offsetY = true },
	zstack = { alignH = true, alignV = true },
	grid = { alignH = true, alignV = true },
	gridrow = { alignH = true, alignV = true, gridSpan = true },
	-- STACKS ONLY, for the shrink pair: the deficit is discovered by a stack's own
	-- main axis (measure PASS 1.5 and arrange's shrink block), and no other branch
	-- calls `src/layout/shrink.luau`'s `stack` at all.
	vstack = { lineAlign = true, layoutPriority = true, shrinkWeight = true },
	hstack = { lineAlign = true, layoutPriority = true, shrinkWeight = true },
	-- ...AND THE WRAPPING STACKS, WHICH ARE NOT THE SAME ROW (round 3 item A).
	-- `lineAlign` is if anything MORE meaningful here — wrapping is what multiplies
	-- the lines it aligns inside — but the SHRINK PAIR is deliberately absent:
	-- wrapping IS the answer to a main-axis deficit, so there is no deficit left for
	-- `layoutPriority`/`shrinkWeight` to share out and a wrapping stack that
	-- accepted them would be accepting-and-ignoring. This row is also why the kind
	-- had to be distinct at all: `auditPlacement` returns nil for a kind it does not
	-- know and polices NOTHING, so a wrapping stack keyed as `hstack` would have
	-- accepted the shrink pair and a wrapping stack keyed as neither would have
	-- accepted every one of the nine.
	vwrap = { lineAlign = true },
	hwrap = { lineAlign = true },
	-- A SCROLLER READS BOTH OFFSETS, not just its axis's. The off-axis nudge is a
	-- no-op today, but the scroll machinery itself writes the pair (scroll
	-- offsetting and the row-culling park, `arrange`'s scroll branch), so pinning
	-- the audit to the authored axis would have it police the framework's own
	-- writes. Narrowing it is a separate question from this defect class.
	scroll = { offsetX = true, offsetY = true },
	-- ...and the two that place a child by RANK or by REGION, never by a placement
	-- prop: a ViewThatFits candidate and a Region's chosen form each get their
	-- container's whole box, or their own measure clamped to it. (`composition` is
	-- absent on purpose — see subtlety 2 above.)
	fits = {},
	region = {},
}
-- kinds whose OWN arrange reads the prop off itself, so it is never inert on
-- them whatever their parent is (subtlety 1 above)
local PLACEMENT_SELF_READ: { [string]: { [string]: boolean } } = {
	zstack = { alignH = true, alignV = true },
}
-- How each kind DOES place a child — the "reason" half of every message. A
-- message that states only the prohibition gets deleted by the next agent who
-- cannot see why it is there; this repo has the scar.
local PLACEMENT_BY: { [string]: string } = {
	vstack = "stacking them down a line",
	hstack = "stacking them across a line",
	vwrap = "stacking them down a column and wrapping into the next one",
	hwrap = "stacking them across a line and wrapping onto the next one",
	zstack = "layering them over its whole box",
	anchor = "pinning them to a corner",
	grid = "flowing them into equal columns",
	gridrow = "seating each one in its row's column",
	scroll = "flowing them along its scroll axis",
	fits = "giving the chosen candidate the whole offer",
	region = "giving the chosen form the region's whole box",
}
-- The shrink pair's advice, one sentence per parent kind: the pair is only ever
-- read by a stack's own shrink pass, so every other kind's message is the same
-- rule plus what that kind DOES do with its children instead.
local function SHRINK_PAIR_INSTEAD(prop: string, insteadDoes: string): string
	return string.format(
		"`%s` is one of the SHRINK pass's two inputs — read only by a `UI.VStack`/`UI.HStack` "
			.. "parent whose main axis came out short; %s",
		prop,
		insteadDoes
	)
end
-- ...and the wrapping stacks' version of it. A wrapping stack's main axis cannot
-- come out short — it wraps instead of overflowing — so the shrink pass is not
-- merely unread here, it has nothing to run on.
local function WRAP_SHRINK_INSTEAD(prop: string): string
	return string.format(
		"`%s` is one of the SHRINK pass's two inputs, and a WRAPPING stack never runs it: its main "
			.. "axis cannot come out short because it wraps instead. Drop `wrap` if you wanted the row "
			.. "squeezed onto one line, or drop `%s`",
		prop,
		prop
	)
end
-- Per (parent kind, prop): the spelling that DOES work there. A refusal that
-- states only the prohibition gets "fixed" by the next agent deleting the check,
-- so every message carries the reason and the way out.
local PLACEMENT_INSTEAD: { [string]: { [string]: string } } = {
	vstack = {
		alignH = "use `lineAlign` (start|center|end|stretch), which a stack does read off each child",
		alignV = "a vstack's cross axis is X — use `lineAlign` (start|center|end|stretch) for it, and "
			.. "`distribute` on the stack for the main axis",
		anchor = "wrap this child in a `UI.Anchor`, which does place by corner",
		offsetX = "wrap this child in a `UI.Anchor` (it reads offsetX/offsetY), or shift it inside the line with `margin`",
		offsetY = "wrap this child in a `UI.Anchor` (it reads offsetX/offsetY), or shift it inside the line with `margin`",
		gridSpan = "`gridSpan` is read only by a `UI.GridRow` cell",
	},
	hstack = {
		alignH = "an hstack's cross axis is Y — use `lineAlign` (start|center|end|stretch) for it, and "
			.. "`distribute` on the stack for the main axis",
		alignV = "use `lineAlign` (start|center|end|stretch), which a stack does read off each child",
		anchor = "wrap this child in a `UI.Anchor`, which does place by corner",
		offsetX = "wrap this child in a `UI.Anchor` (it reads offsetX/offsetY), or shift it inside the line with `margin`",
		offsetY = "wrap this child in a `UI.Anchor` (it reads offsetX/offsetY), or shift it inside the line with `margin`",
		gridSpan = "`gridSpan` is read only by a `UI.GridRow` cell",
	},
	-- THE WRAPPING PAIR (round 3 item A). Same advice as the stack it is a mode of,
	-- plus the one message that is genuinely different: the shrink pair is not
	-- "read by a stack whose axis came out short" here, because this stack's axis
	-- CANNOT come out short — it wraps instead. `WRAP_SHRINK_INSTEAD` says exactly
	-- that rather than pointing an author at a pass that will never run.
	vwrap = {
		alignH = "use `lineAlign` (start|center|end|stretch), which a wrapping stack does read off each child",
		alignV = "a wrapping vstack's cross axis is X — use `lineAlign` (start|center|end|stretch) for one "
			.. "child in its line, `align` for where the block of lines sits, and `distribute` for the "
			.. "main axis of each line",
		anchor = "wrap this child in a `UI.Anchor`, which does place by corner",
		offsetX = "wrap this child in a `UI.Anchor` (it reads offsetX/offsetY), or shift it inside the line with `margin`",
		offsetY = "wrap this child in a `UI.Anchor` (it reads offsetX/offsetY), or shift it inside the line with `margin`",
		gridSpan = "`gridSpan` is read only by a `UI.GridRow` cell",
		layoutPriority = WRAP_SHRINK_INSTEAD("layoutPriority"),
		shrinkWeight = WRAP_SHRINK_INSTEAD("shrinkWeight"),
	},
	hwrap = {
		alignH = "a wrapping hstack's cross axis is Y — use `lineAlign` (start|center|end|stretch) for one "
			.. "child in its line, `align` for where the block of lines sits, and `distribute` for the "
			.. "main axis of each line",
		alignV = "use `lineAlign` (start|center|end|stretch), which a wrapping stack does read off each child",
		anchor = "wrap this child in a `UI.Anchor`, which does place by corner",
		offsetX = "wrap this child in a `UI.Anchor` (it reads offsetX/offsetY), or shift it inside the line with `margin`",
		offsetY = "wrap this child in a `UI.Anchor` (it reads offsetX/offsetY), or shift it inside the line with `margin`",
		gridSpan = "`gridSpan` is read only by a `UI.GridRow` cell",
		layoutPriority = WRAP_SHRINK_INSTEAD("layoutPriority"),
		shrinkWeight = WRAP_SHRINK_INSTEAD("shrinkWeight"),
	},
	zstack = {
		anchor = "use `alignH`/`alignV` (start|center|end), which a zstack does read off each child",
		offsetX = "wrap this child in a `UI.Anchor` (it reads offsetX/offsetY), or use `margin` to inset it",
		offsetY = "wrap this child in a `UI.Anchor` (it reads offsetX/offsetY), or use `margin` to inset it",
		lineAlign = "`lineAlign` is a STACK's word — under a zstack use `alignH`/`alignV`",
		gridSpan = "`gridSpan` is read only by a `UI.GridRow` cell",
		layoutPriority = SHRINK_PAIR_INSTEAD(
			"layoutPriority",
			"a zstack layers its children over its whole box and never negotiates a deficit"
		),
		shrinkWeight = SHRINK_PAIR_INSTEAD(
			"shrinkWeight",
			"a zstack layers its children over its whole box and never negotiates a deficit"
		),
	},
	anchor = {
		alignH = "an Anchor places by corner — use `anchor` (topLeft…bottomRight) with `offsetX`/`offsetY`",
		alignV = "an Anchor places by corner — use `anchor` (topLeft…bottomRight) with `offsetX`/`offsetY`",
		lineAlign = "`lineAlign` is a STACK's word — under an Anchor use `anchor` (topLeft…bottomRight)",
		gridSpan = "`gridSpan` is read only by a `UI.GridRow` cell",
		layoutPriority = SHRINK_PAIR_INSTEAD(
			"layoutPriority",
			"an Anchor pins by corner and never negotiates a deficit"
		),
		shrinkWeight = SHRINK_PAIR_INSTEAD("shrinkWeight", "an Anchor pins by corner and never negotiates a deficit"),
	},
	grid = {
		anchor = "a grid places each cell in its column — wrap this cell's content in a `UI.Anchor` inside the cell",
		offsetX = "a grid places each cell in its column — wrap this cell's content in a `UI.Anchor` inside the cell",
		offsetY = "a grid places each cell in its column — wrap this cell's content in a `UI.Anchor` inside the cell",
		lineAlign = "`lineAlign` is a STACK's word — inside a grid cell use `alignH`/`alignV`",
		gridSpan = "`gridSpan` is a ROW grid's word — it is read off a `UI.GridRow`'s cells, not off a flow grid's",
		layoutPriority = SHRINK_PAIR_INSTEAD("layoutPriority", "a grid gives every cell its column"),
		shrinkWeight = SHRINK_PAIR_INSTEAD("shrinkWeight", "a grid gives every cell its column"),
	},
	gridrow = {
		anchor = "a row places each cell in its column — wrap this cell's content in a `UI.Anchor` inside the cell",
		offsetX = "a row places each cell in its column — wrap this cell's content in a `UI.Anchor` inside the cell",
		offsetY = "a row places each cell in its column — wrap this cell's content in a `UI.Anchor` inside the cell",
		lineAlign = "`lineAlign` is a STACK's word — inside a grid cell use `alignH`/`alignV`",
		layoutPriority = SHRINK_PAIR_INSTEAD(
			"layoutPriority",
			"a row seats each cell in its column (use `gridSpan` to cover more of them)"
		),
		shrinkWeight = SHRINK_PAIR_INSTEAD(
			"shrinkWeight",
			"a row seats each cell in its column (use `gridSpan` to cover more of them)"
		),
	},
	scroll = {
		alignH = "a scroller stretches its children across the cross axis — wrap this child in a "
			.. "`UI.ZStack` (which reads alignH/alignV) or give it a `width` and a `lineAlign`",
		alignV = "a scroller stretches its children across the cross axis — wrap this child in a "
			.. "`UI.ZStack` (which reads alignH/alignV) or give it a `height`",
		anchor = "wrap this child in a `UI.Anchor`, which does place by corner",
		lineAlign = "a scroller's flow is not a stack line — wrap this child in a `UI.VStack`/`UI.HStack`",
		gridSpan = "`gridSpan` is read only by a `UI.GridRow` cell",
		layoutPriority = SHRINK_PAIR_INSTEAD(
			"layoutPriority",
			"a scroller has no deficit to share out, which is what scrolling means (wrap these children in a stack if you want them squeezed instead)"
		),
		shrinkWeight = SHRINK_PAIR_INSTEAD(
			"shrinkWeight",
			"a scroller has no deficit to share out, which is what scrolling means (wrap these children in a stack if you want them squeezed instead)"
		),
	},
	fits = {
		DEFAULT = "a ViewThatFits candidate is given the whole offer or its own measure clamped to it — "
			.. "put the placement prop on a container INSIDE the candidate",
	},
	region = {
		DEFAULT = "a UI.Region hands its chosen form the region's whole box — put the placement prop on a "
			.. "container INSIDE the form",
	},
}

-- The parent-side audit, run once per node per tree build by
-- `renderer.toLayoutNode` and reported by `arrange` (so it is gated by
-- `hiddenDepth` and replayed by the incremental-layout reuse path exactly like
-- the overflow diagnostic beside it). Returns nil — the overwhelmingly common
-- answer — rather than an empty table, so a clean tree allocates nothing.
--
-- `childKinds` is parallel to `children`; the caller has them already.
function placement_audit.auditPlacement(
	parentKind: string,
	parentId: string,
	children: { any }
): { { node: string, issue: string, filedBy: string } }?
	local reads = PLACEMENT_READS[parentKind]
	if reads == nil then
		return nil -- a kind that places no children, or one this table does not police
	end
	local found: { { node: string, issue: string, filedBy: string } }? = nil
	for _, child in children do
		-- ONE field test for the overwhelmingly common case. `placementProps` is
		-- set by `renderer.toLayoutNode` on the same line that already reads all
		-- seven values, so a node carrying none costs this comparison and nothing
		-- else — the difference between a measurable arrange regression and none.
		if (child :: any).placementProps == nil then
			continue
		end
		local selfRead = PLACEMENT_SELF_READ[child.kind]
		for _, prop in PLACEMENT_PROPS do
			if (child :: any)[prop] == nil or reads[prop] then
				continue
			end
			if selfRead ~= nil and selfRead[prop] then
				continue -- the child's OWN arrange reads it (a zstack's alignH/alignV)
			end
			local advice = PLACEMENT_INSTEAD[parentKind]
			local instead = if advice ~= nil then (advice[prop] or advice.DEFAULT) else nil
			found = found or {}
			table.insert(found :: any, {
				node = child.id,
				-- THE FILER, not the named node (RED-TEAM Milestone 1, HIGH 2). Every
				-- other diagnostic in this file is filed under the node that files it,
				-- so the incremental replay gate could read `d.node` and be right. This
				-- one cannot: `arrange` files it while walking the PARENT, and names the
				-- offending CHILD. Without this stamp the gate replayed a finding the
				-- walked parent had already filed fresh, once more every layout-dirty
				-- frame, forever.
				filedBy = parentId,
				issue = string.format(
					"`%s` is a placement prop this parent never reads: a %s's arrange places its "
						.. "children by %s, so `%s` here is accepted and then ignored — nothing moves. %s",
					prop,
					parentKind,
					PLACEMENT_BY[parentKind] or "its own rule",
					prop,
					instead or "put it on a parent that reads it"
				),
			})
		end
	end
	return found
end

--[[ ===== THE SETTLE-TIME CONTAINMENT FINDING (2026-08-21) ==================

	`docs/lessons/the-solver-already-told-you.md` is the standing lesson, and its
	one line is that the solver already knows — every overflow, every collapsed
	content box, every inert prop — on a channel somebody has to ask. THIS IS THE
	ONE THING IT DID NOT KNOW HOW TO SAY. Every overflow finding in `solver.luau`
	is derived from a MEASURE compared against an offer: "content overflows this
	vstack by 44px", "this child overflows its zstack by 12x0px", "the wrapped
	lines overflow this hwrap". Not one of them is derived from the RECT the child
	was finally given.

	SO THIS ONE IS, AND IT IS SCOPED BY MEASUREMENT RATHER THAN BY INTENTION.
	The first draft policed every parent that places a child, and the suite
	answered with **21,916 findings**: 13,851 from `anchor`, whose entire contract
	is to place a child wherever the author says (a badge on a corner, a thumb at
	the end of a groove); 3,609 from `zstack`, which layers by definition and
	already has its own measure-side overlap finding and its own
	`intentionalOverlap` opt-out; and 4,103 on the MAIN axis of a stack, every one
	of them a second telling of the "content overflows this vstack by Npx" finding
	that fires two lines above the loop. A finding that fires 21,916 times on a
	green library is not a diagnostic, it is a channel people learn to mute.

	WHAT IS LEFT IS THE HOLE: the CROSS axis of a flow stack. A stack's own
	arithmetic is supposed to guarantee it — `crossSize` is `min(desired,
	crossAvail)` — so a child landing outside on that axis means the guarantee
	broke (margins wider than the box are one live way, found by fuzz), and
	NOTHING reported it. Measured on the same run: **41 occurrences suite-wide,
	all of them on adversarial fuzz trees and not one on a shipped fixture or
	example**, which is what a diagnostic scoped to a real defect looks like.

	The same shape as the rule three files over: "the main axis has now been
	reported by name and by number; leave the overlap finding below the CROSS axis
	only, so a row that is ALSO too wide still says so exactly once."

	Reported, never fatal — the trade every finding in this family makes: an
	honestly cramped offer produces the same geometry, and stopping a screen to
	report an authoring mistake is the worse outcome.

	STILL UNREPORTED, MEASURED AND BOOKED rather than shipped silently: a
	composition REGION placed below its composition's own content box fired 312
	times on one scenario (`/HudScreen/Hud/*`). That is a real class — the
	collision finding compares regions against each OTHER and never against the
	box — but it is a defect to investigate rather than a rule to add in the same
	breath, and the adapter-side containment harness is the right instrument for
	it.
]]

-- sub-pixel noise is not a defect: rects are rounded and a half-pixel of
-- accumulated alignment is not something an author can act on
local CONTAIN_SLOP = 0.5

local CONTAIN_ADVICE = "give the box room — a `minMax` FLOOR rather than a fixed CAP — trim the child's "
	.. 'margin, or say so with overflow = "clip"'

local ROUTED_KINDS: { [string]: boolean } = {
	-- a canvas absorbs its own content by construction
	scroll = true,
	-- a wrapping stack reports its own cross-axis spill and its own clamped
	-- children, by name and by number, one layer up
	hwrap = true,
	vwrap = true,
}

--[[ Does this parent route overflow away on its own account? `overflow` is the
	author's word and covers both axes; the kind table above covers the two
	families whose whole job is to absorb, or to report for themselves. Exported
	rather than folded into `containment` because the solver checks it before it
	pays for `axisAbsorbs`, and one reading of "routed" is the point. ]]
function placement_audit.routesOverflow(parent: any): boolean
	local declared = parent.overflow
	if declared == "clip" or declared == "scroll" or declared == "intentionalOverlap" then
		return true
	end
	return ROUTED_KINDS[parent.kind] == true
end

--[[ THE FINDING, OR NIL — which is the overwhelmingly common answer, so a
	contained tree allocates nothing.

	`x`/`y`/`w`/`h` are the parent's CONTENT box (its padding already spent), which
	is the box the child was placed into. `axisIsX` names the axis to police: the
	caller passes its stack's CROSS axis, and passes it only after establishing
	that the parent cannot grow on it (`axisAbsorbs`) and routes no overflow. Both
	of those live in `solver.luau` because both are its own predicates, and
	duplicating either here is the copy-goes-stale failure every seam in this
	directory exists to avoid. ]]
function placement_audit.containment(
	parent: any,
	child: any,
	rect: { x: number, y: number, w: number, h: number },
	x: number,
	y: number,
	w: number,
	h: number,
	axisIsX: boolean
): { { node: string, issue: string, filedBy: string, edge: string, overhang: number } }?
	local nearOver = if axisIsX then x - rect.x else y - rect.y
	local farOver = if axisIsX then (rect.x + rect.w) - (x + w) else (rect.y + rect.h) - (y + h)
	if nearOver <= CONTAIN_SLOP and farOver <= CONTAIN_SLOP then
		return nil
	end
	local found: { { node: string, issue: string, filedBy: string, edge: string, overhang: number } } = {}
	for _, pair in
		{ { if axisIsX then "left" else "top", nearOver }, { if axisIsX then "right" else "bottom", farOver } }
	do
		local edge, over = pair[1] :: string, pair[2] :: number
		if over <= CONTAIN_SLOP then
			continue
		end
		table.insert(found, {
			node = child.id,
			-- filed by the PARENT and naming the CHILD, the stamp the incremental
			-- replay gate reads (`solve`'s replay loop): the node that FILES a
			-- finding is the one whose being skipped could leave it stale
			filedBy = parent.id,
			-- FIRST-CLASS FIELDS, not a substring of the sentence. A harness asserts
			-- on the edge and the number without parsing English, which is the whole
			-- difference between a diagnostic and a log line
			edge = edge,
			overhang = over,
			issue = string.format(
				"'%s' is placed %dpx past the %s edge of this %s's content box on the CROSS axis — a stack "
					.. "sizes its children to that box, so landing outside it means something (a margin "
					.. "wider than the box is the usual one) beat the clamp, and the child paints over "
					.. "whatever sits beyond that edge (%s)",
				child.id,
				math.ceil(over),
				edge,
				parent.kind,
				CONTAIN_ADVICE
			),
		})
	end
	return if #found > 0 then found else nil
end

return placement_audit
