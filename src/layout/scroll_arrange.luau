--!strict
--[[ scroll_arrange — the ARRANGE half of `UI.ScrollView`, lifted out of
	`layout/solver.luau` on 2026-09-04 (Plan C, C3) for the Source-write headroom
	the anchor branch's clean-child skip needed. The solver stood 258 characters
	from the campaign's 197,500 STOP line with the arm in the tree, and its
	`source-cap-ledger.md` row has named this block as the seam to take since
	2026-08-22; the rule at the head of that ledger is that the room is taken
	FIRST, in its own behaviour-neutral commit, and this is it.

	Public interface, one entry point and one type:

	  `scroll_arrange.arrange(deps, ctx, node, rect, innerX, innerY, innerW,
	      innerH, gap, pt, pr, pb, pl, out)`
	      places a `scroll` node's children along its axis, having re-measured
	      them at the viewport (twice, when the bar reservation narrows it), and
	      publishes the four facts a scroll host owes the commit: `contentSize`,
	      the `padding` it actually SPENT, the `barInset` it reserved, and the
	      resolved `overflow`.

	`scroll_arrange.Deps` is what it needs from the solver: the two recursive
	passes and four pure readers. It requires `../tokens/chrome_slots` for the
	all-or-nothing leading-bleed floor and nothing else.

	WHY IT IS A ONE-WAY SPLIT DESPITE MUTATING THE SCOPE. The scope pair
	(`pushContainer` / `restoreScope`) is the reason the T6 round declined this
	seam and it is carried here as two Deps functions rather than reimplemented:
	this module never touches `ctx.containerW`/`containerH`/`scopeKey` itself, it
	asks the solver to, so the memo-key arming rule stays in the one file that
	owns it. Everything else it reads off `ctx` is a plain per-solve field
	(`scrollBarReserve`, `hiddenDepth` is not read here at all), and the only
	things it writes are `out[node.id]`'s four published facts — the same table
	the caller already wrote. No solver local is captured, no state lives at
	module level, and nothing here requires the solver back.

	`tests/scroll_arrange_seam.spec.luau` is those properties mechanised; the
	BEHAVIOUR is unchanged and `tests/scroll.spec.luau`, `tests/scroll_bar_reserve.spec.luau`
	and the device sweep are what say so. ]]
local chrome_slots = require("../tokens/chrome_slots")
local solveCtx = require("./solve_ctx")

export type Rect = solveCtx.Rect

--[[ WHAT THIS MODULE ASKS THE SOLVER FOR, and no more. `measure` and `arrange`
	are the two recursive passes — forwarders on the solver side, because both are
	forward locals there and a by-value record would capture nil (`GRID_DEPS` says
	the same about its own). `pushContainer`/`restoreScope` are the scope pair; the
	solver owns what a scope key is made of and this module only brackets one. ]]
export type Deps = {
	measure: (ctx: any, node: any, maxW: number, maxH: number) -> (number, number),
	arrange: (ctx: any, node: any, rect: Rect, out: { [string]: any }) -> (),
	dim: (node: any, axis: string) -> any,
	offsetPx: (value: any, basis: number) -> number,
	pushContainer: (ctx: any, w: number, h: number) -> (),
	restoreScope: (ctx: any, w: number, h: number, key: string) -> (),
}

local scroll_arrange = {}

function scroll_arrange.arrange(
	deps: Deps,
	ctx: any,
	node: any,
	rect: Rect,
	innerX: number,
	innerY: number,
	innerW: number,
	innerH: number,
	gap: number,
	pt: number,
	pr: number,
	pb: number,
	pl: number,
	out: { [string]: any }
)
	-- BOUND AS LOCALS so the body below is the solver's, line for line: a moved
	-- block that had to be rewritten to move is not a seam, it is a rewrite, and
	-- the review that follows one is a different review.
	local measure, arrange = deps.measure, deps.arrange
	local dim, offsetPx = deps.dim, deps.offsetPx
	local pushContainer, restoreScope = deps.pushContainer, deps.restoreScope
	local axis = node.axis or "y"
	local isX = axis == "x"
	local contentW, contentH = 0, 0
	local childSizes = {}
	-- SCROLLBAR RESERVATION (director review 2026-07-24). The engine draws the
	-- scrollbar INSIDE the region, overlapping whatever the solver put there:
	-- live, a 328px-wide scroll host reported AbsoluteWindowSize 320 while
	-- content was laid out to the full 328, so the right 8px of every control
	-- in the fixture sat underneath the bar. Reserve the bar's thickness off
	-- the CROSS axis whenever the content actually overflows — which is exactly
	-- when the engine shows it. Measuring twice is the cost of not guessing.
	-- The threshold is stable: reserving makes the cross axis narrower, which
	-- can only make the scroll axis longer, so a region that overflowed at the
	-- full width still overflows at the reserved width.
	local function measureAll(crossLimitW: number, crossLimitH: number)
		local cw, ch = 0, 0
		local sizes = {}
		for _, child in node.children or {} do
			local w, h = measure(
				ctx,
				child,
				if isX then math.huge else crossLimitW,
				if axis == "y" then math.huge else crossLimitH
			)
			table.insert(sizes, { w = w, h = h })
			if isX then
				cw += w
				ch = math.max(ch, h)
			else
				cw = math.max(cw, w)
				ch += h
			end
		end
		local g = if #sizes > 1 then gap * (#sizes - 1) else 0
		if isX then
			cw += g
		else
			ch += g
		end
		return sizes, cw, ch
	end
	-- THE CONTAINER THIS SUBTREE SIZES AGAINST (§2.5), pushed around EVERY
	-- measure and every arrange below — and re-pushed after the scrollbar
	-- reservation, because reserving the bar makes the viewport genuinely
	-- narrower and a page sized against the pre-reserve number would sit under
	-- the bar. Same fact the reservation already re-measures for.
	local restoreW, restoreH, restoreKey = ctx.containerW, ctx.containerH, ctx.scopeKey
	local reserve = ctx.scrollBarReserve
	local spentReserve = 0
	pushContainer(ctx, innerW, innerH)
	childSizes, contentW, contentH = measureAll(innerW, innerH)
	if reserve > 0 then
		local overflows = if isX then contentW > innerW else contentH > innerH
		if overflows then
			if isX then
				innerH = math.max(0, innerH - reserve)
			else
				innerW = math.max(0, innerW - reserve)
			end
			spentReserve = reserve
			pushContainer(ctx, innerW, innerH)
			childSizes, contentW, contentH = measureAll(innerW, innerH)
		end
	end
	-- the gaps are already folded into contentW/contentH by measureAll: the
	-- flow cursor advances by gap between children, so the extent must include
	-- them or the native canvas under-covers and the last row's tail is
	-- unreachable (migration-agent finding 2026-07-23, native substrate)
	--
	-- THE CROSS AXIS IS CLAMPED TO THE WINDOW (director live report,
	-- 2026-08-09): this is a SINGLE-axis scroller, so content on the other
	-- axis is unreachable by construction — but a nested cross-axis
	-- carousel MEASURES at its content width (fill measures as content),
	-- and publishing that measure as the canvas made the engine draw a
	-- horizontal scrollbar on a Y scroller, straight through the tab dock
	-- beneath it. The canvas the adapter is given must never exceed the
	-- window on an axis nobody can scroll.
	if isX then
		contentH = math.min(contentH, innerH)
	else
		contentW = math.min(contentW, innerW)
	end

	--[[ THE LEADING EDGE'S OWN CHROME BLEED, SPENT FLOOR-AWARE, AFTER THIS
		NODE'S OWN CHILDREN ARE ALREADY MEASURED (task SHOWCASE3; supersedes
		`9eb095a`, reverted). The cross axis above already reserves
		`chromeBleed` unconditionally, folded into `node.padding` BEFORE any
		of this node's children were measured — safe there because nothing
		has yet measured it collapsing a real box. The leading edge (top for
		a y-axis scroller, left for an x-axis one) is different for the
		reason `layout_node.luau`'s own comment gives: there is no canvas
		before scroll position 0 to grow into, so the only way to show a
		first child's own glow is real padding, and real padding taken from
		a box that cannot afford it is a blank scroller. `rect.h`/`rect.w`
		is the box this node ACTUALLY resolved to — the fact the pre-solve
		conversion never has — so the same all-or-nothing floor a themed
		control's own contentInsets already spend against applies here too:
		afford it only if the box survives.

		SPENT HERE, AFTER `measureAll`, AND THAT IS LOAD-BEARING. Folding it
		into `pl`/`pt` before `pushContainer`/`measureAll` ran shrank
		`ctx.containerW` for THIS node's own children during their own
		measurement — a live fact every descendant already answers against
		— and measured to tip an already-marginal `tab_view` strip into a
		text wrap it did not have, at `desktop-studio-1320` under Sci-Fi HUD
		(a NEW "content overflows this vstack" finding, not the collapse
		`9eb095a` is named for). Every child above is already measured and
		arranged against the UNBLED box; this only moves the CURSOR's start
		and `padding` (below) — NOT `contentSize`, which stays the pure
		content sum `measureAll` already reports (the adapter is the one
		that adds padding to it for the canvas it builds, exactly as it
		already does for the cross-axis reservation folded into `pl`/`pr`
		above) — the same non-interference the trailing edge's own canvas
		allowance (`render/commit_walks.luau`) already keeps. ]]
	local leadingSpend = 0
	if type(node.leadingBleed) == "number" and node.leadingBleed > 0 then
		local extent = if isX then rect.w else rect.h
		local authored = if isX then pl + pr else pt + pb
		leadingSpend = chrome_slots.spendInset(extent, authored, node.leadingBleed)
	end
	out[node.id].contentSize = { w = contentW, h = contentH }
	-- ...and the padding this solve actually SPENT, published so the canvas the
	-- adapter is given is built from the same number the content was measured
	-- inside. The renderer used to re-derive it from the authored prop, which
	-- silently drops whatever a theme's `scrollbar` slot reserved (2026-07-27).
	out[node.id].padding = {
		top = pt + (if not isX then leadingSpend else 0),
		right = pr,
		bottom = pb,
		left = pl + (if isX then leadingSpend else 0),
	}
	--[[ ...AND THE BAR GUTTER THIS HOST ACTUALLY SPENT (director report
		2026-08-14: "the scroll bar always overlaps content", and its follow-up
		"it should apply to both horizontal and vertical ones").

		The reservation above narrows the host's CONTENT BOX, so everything
		inside it stops short of the bar — correct, and invisible to anything
		outside the subtree. A node that has to line up ACROSS that boundary is
		the case it cannot serve: a Table's header is a SIBLING of its scrolling
		body, so the body's columns resolved against `innerW` while the header's
		resolved against the full frame, and every column edge drifted by the
		reserve (worsening left to right, because a `fill` column's share of the
		difference accumulates). Measured live at `table-columns`: body window
		875 against a header laid out to 883, the trailing column 8px under the
		bar.

		So the number is PUBLISHED rather than left implicit, keyed by the side
		it was taken from — `right` for a Y scroller, `bottom` for an X one, so
		a consumer pays it on the correct edge instead of assuming width. Nil
		when nothing was reserved (a host whose content fits shows no bar and
		must not be paid for), which is exactly the conditionality a sibling
		cannot re-derive for itself.

		READ BY: `renderer.controller.scrollBarInsetOf` -> `newTable`'s header
		padding. A fixed box cannot hold a theme's frame, and the general rule
		this is the far end of is: reserving room is only half
		of it, something has to SPEND the reservation — and here the node that
		must spend it lives outside the subtree that made it. ]]
	out[node.id].barInset = if spentReserve > 0
		then { right = if isX then 0 else spentReserve, bottom = if isX then spentReserve else 0 }
		else nil
	out[node.id].overflow = if (axis == "y" and contentH > innerH) or (axis == "x" and contentW > innerW)
		then "scroll"
		else node.overflow
	-- the flow cursor advances along the SCROLL axis; `leadingSpend` (above)
	-- starts it `bleed` further in on the leading edge only — the trailing
	-- edge needs no such nudge, its own canvas allowance already covers it
	local cursor = (if isX then innerX else innerY) + leadingSpend
	for i, child in node.children or {} do
		local size = childSizes[i]
		-- cross-axis fill children stretch to the scroll viewport
		local w = if isX then size.w else math.min(size.w, innerW)
		if not isX and dim(child, "w").type == "fill" then
			w = innerW
		end
		local h = if isX then math.min(size.h, innerH) else size.h
		if isX and dim(child, "h").type == "fill" then
			h = innerH
		end
		-- offsetX/offsetY are arrange-time adjustments (scroll offsetting +
		-- row culling park, Phase 4 touch-scroll design); the flow cursor is
		-- unaffected so siblings keep their slots
		local childRect: Rect = if isX
			then { x = cursor + offsetPx(child.offsetX, innerW), y = innerY, w = w, h = h }
			else { x = innerX, y = cursor + offsetPx(child.offsetY, innerH), w = w, h = h }
		arrange(ctx, child, childRect, out)
		cursor += (if isX then size.w else size.h) + gap
	end
	restoreScope(ctx, restoreW, restoreH, restoreKey)
end

return scroll_arrange
