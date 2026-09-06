--!strict
--[[ THE BOX REPORTS OF `arrange`, lifted out of `layout/solver.luau` on 2026-09-02
	because the wicked-fast round's translate arm needed Source-write headroom the
	solver did not have (`tools/lune/verify/data/source-cap-ledger.md`, and the head
	of that document: take the room FIRST, in its own behaviour-neutral commit).

	IT IS THE CHEAPEST ONE-WAY SPLIT LEFT IN THAT FUNCTION and needs no `Deps` at
	all — no `measure`, no `arrange`, no forward local of any kind. Every input is a
	value the caller already holds (the `ctx`, the `node`, the resolved `rect` and
	the four padding sides it derived the content box from) and the only output is
	`table.insert` into `ctx.diagnostics`, which is the same list the caller writes.
	So no mutable upvalue of the solver crosses this boundary and no behaviour
	changes: the diagnostic cases in `tests/layout.spec.luau`,
	`tests/containment_diagnostic.spec.luau` and `tests/chrome_inset_yield.spec.luau`
	are the proof, not this comment.

	WHY THE FOUR MESSAGES SIT TOGETHER. They are the reports a node can only make
	about ITS OWN BOX once the box is resolved — a theme too big for the control, an
	icon floor that was refused, a content box padding emptied, and a child holding
	a placement prop this parent will never read. All four are gated on
	`ctx.hiddenDepth == 0` (a losing ViewThatFits candidate does not shout) and all
	four are replayed by the reuse path, which is the pair of properties that makes
	them one block rather than four. ]]
--[[ THE TWO PURE MODULES THE CONTAINMENT REPORT READS, and both are safe to
	import here for the same reason `solver.luau` imports them: neither requires
	anything back (`placement_audit` says so in its own header, and re-declares the
	node schema as `any` rather than importing the solver's for exactly that
	reason), so this file stays a leaf. ]]
local placementAudit = require("./placement_audit")
local measureFacts = require("./measure_facts")
local dim = measureFacts.dim
local axisAbsorbs = measureFacts.axisAbsorbs

local arrange_reports = {}

--[[ Reported after the content box is derived and BEFORE the leaf return (director
	report 2026-07-28): a leaf Button is `kind = "box"` and returns immediately, so a
	report placed below that return is structurally unreachable for the whole class
	of node whose own TEXT is its content — which is the shape defect 3 arrived in. ]]
function arrange_reports.box(
	ctx: any,
	node: any,
	rect: { x: number, y: number, w: number, h: number },
	innerW: number,
	innerH: number,
	pt: number,
	pr: number,
	pb: number,
	pl: number
)
	-- ZERO CONTENT BOX (found live under pixel-quest: `barTrack`
	-- contentInsets of 8 on all four sides over a track the package resolved to
	-- 8px tall, so the fill solved to max(0, 8 - 16) = 0 and the download bar
	-- showed a trough, two heart caps and no value — with zero diagnostics). A
	-- node that has children and no room to put them cannot draw them: the
	-- padding won and the content is invisible. Reported, never repaired —
	-- silently clamping the padding would move shipped geometry, and the whole
	-- point is that this condition stops being invisible.
	--
	-- `rect.w > 0` is the guard that keeps it a diagnosis: a host that was already
	-- zero (a hidden ViewThatFits candidate, a 0-percent fill) is a different
	-- condition and its padding is not what emptied it. `chromeSlot` is set by the
	-- renderer wherever a slot's `contentInsets` became this padding, so the
	-- message names where the numbers came from.
	-- THE CHROME INSET THAT COULD NOT BE SPENT (director report 2026-07-28). The
	-- renderer already repaired the geometry — this is the report that it had to,
	-- which is what an author needs to know: the control is smaller than the theme
	-- it is wearing. It is a SEPARATE message from the collapse below because it
	-- describes the opposite outcome (repaired, not broken) and pointing an author
	-- at "nothing can draw" for a control that now draws fine would be a lie.
	if ctx.hiddenDepth == 0 and node.chromeYield ~= nil then
		local yield_ = node.chromeYield
		if yield_.x ~= nil then
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = string.format(
					"the '%s' chrome contentInsets could not be spent on x: %dpx of border on a %dpx "
						.. "width already holding %dpx of padding — the inset was given back so the "
						.. "content still draws, but this control is smaller than its theme expects",
					yield_.slot,
					yield_.x,
					rect.w,
					pl + pr
				),
			})
		end
		if yield_.y ~= nil then
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = string.format(
					"the '%s' chrome contentInsets could not be spent on y: %dpx of border on a %dpx "
						.. "height already holding %dpx of padding — the inset was given back so the "
						.. "content still draws, but this control is smaller than its theme expects",
					yield_.slot,
					yield_.y,
					rect.h,
					pt + pb
				),
			})
		end
	end

	--[[ ...AND THE SIZE FLOOR THAT WAS REFUSED, next to the yield above because it
			is the same fact about a different number: a control too small for what its
			package asks it to wear. The disc is NOT broken — it keeps the room the host
			reserved and the paint seam draws the picture at the size that fits — so the
			message says what the author can act on, which is the package's own two
			metrics disagreeing. ]]
	if ctx.hiddenDepth == 0 and node.sizeRefused ~= nil then
		local refused = node.sizeRefused
		table.insert(ctx.diagnostics, {
			node = node.id,
			issue = string.format(
				"the '%s' icon floor wanted a %dpx disc and the host reserved %dpx — the floor was "
					.. "refused so this control stays inside the room it was given and the picture is "
					.. "drawn at the size that fits, but this theme's icon is bigger than this control",
				tostring(refused.icon),
				refused.want,
				refused.reserved
			),
		})
	end

	-- A LEAF'S TEXT IS CONTENT TOO (director report 2026-07-28). This was guarded
	-- on `#children > 0`, so a Button whose own label IS its content — every leaf
	-- Button in the library — could collapse to a zero content box and report
	-- nothing at all. That is exactly the shape defect 3 arrived in.
	local hasContent = (node.children ~= nil and #node.children > 0) or (node.text ~= nil and node.text ~= "")
	if ctx.hiddenDepth == 0 and hasContent then
		local from = if node.chromeSlot ~= nil then ` (the '{node.chromeSlot}' chrome contentInsets)` else ""
		if innerW <= 0 and rect.w > 0 then
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = string.format(
					"content box collapses to 0px on x: padding %d + %d on a %dpx width%s — "
						.. "nothing inside this %s can draw",
					pl,
					pr,
					rect.w,
					from,
					node.kind
				),
			})
		end
		if innerH <= 0 and rect.h > 0 then
			table.insert(ctx.diagnostics, {
				node = node.id,
				issue = string.format(
					"content box collapses to 0px on y: padding %d + %d on a %dpx height%s — "
						.. "nothing inside this %s can draw",
					pt,
					pb,
					rect.h,
					from,
					node.kind
				),
			})
		end
	end

	-- ...and the OTHER thing this node's own box cannot show you: a child holding
	-- a placement prop this node's arrange will never read (§2.1). The finding is
	-- computed at tree-build time; reporting it HERE is what buys it the
	-- `hiddenDepth` gate (a losing ViewThatFits candidate does not shout) and the
	-- reuse replay, the same two properties the overflow diagnostic above has.
	if node.inertPlacement ~= nil and ctx.hiddenDepth == 0 then
		for _, finding in node.inertPlacement do
			table.insert(ctx.diagnostics, finding)
		end
	end
end

--[[ THE CONTAINMENT CHECK CAME HERE ON 2026-09-04 (Plan C, T3 fix round 1) for the
	same reason `arrange_reports.box` did, and the ledger row that named it as the
	next candidate is the one this pays off: `layout/solver.luau` stood 55
	characters inside the campaign's 197,500 STOP band, and Plan C's T5 edits that
	file next. Behaviour is byte-identical — the block moved verbatim, comments
	included, with its two solver-local types widened to `any` the way every other
	seam out of that file widens them.

	IT BELONGS HERE ON ITS MERITS, not only on its size. Every other function in
	this module is a report a node makes about its own box once that box is
	resolved, gated on `ctx.hiddenDepth == 0`, whose only output is `table.insert`
	into `ctx.diagnostics`. This one is exactly that shape — it simply reports about
	a CHILD's box rather than the node's own.

	ONE-WAY BY THE SAME TEST AS THE REST OF THE FILE: it reads two `ctx` fields
	(`hiddenDepth`, `diagnostics`) and calls four module-level pure helpers
	(`placement_audit.routesOverflow`/`.containment`, `measure_facts.dim`/
	`.axisAbsorbs`), every one of which the solver itself imports from a module that
	imports nothing back. No `Deps` record, no forward local, no mutable upvalue of
	the solver crosses the boundary. `tests/arrange_reports_seam.spec.luau` is that
	property mechanised; `tests/containment_diagnostic.spec.luau` is the behaviour.

	THE CALLER DID NOT MOVE. `solver.luau` still passes it to `stackLib.arrange` as
	a call-site argument beside `arrange`, because `stack.luau` takes both that way
	and neither belongs in `STACK_DEPS`. ]]
--[[ THE CONTAINMENT CHECK, ON THE ONE AXIS NOTHING ELSE WATCHES.

	Every other overflow finding in this file is derived from a MEASURE against an
	offer. This one is derived from the RECT the child was finally given, which is
	the only instrument that can see a box placed outside its parent by ARITHMETIC
	rather than by size — the class the solver already knew about, and the
	property `tests/lib/overflow_guard.luau` now asserts from the
	adapter side after every settle.

	IT POLICES THE STACK'S CROSS AXIS AND NOTHING ELSE, and the scope was measured
	rather than chosen: `./placement_audit` carries the counts. The main axis is
	already reported by name and by number two lines above the loop; `zstack` and
	`anchor` place children outside their box by design and have their own finding
	and their own opt-out. What is left is the axis a stack's own `min(desired,
	crossAvail)` is supposed to guarantee — so a child outside it means the
	guarantee broke, and until now nothing said so.

	TWO COMPARISONS ON THE COMMON PATH: a contained child never reaches
	`axisAbsorbs`, never reaches the route test and never allocates.
]]
function arrange_reports.containment(
	ctx: any,
	node: any,
	child: any,
	rect: { x: number, y: number, w: number, h: number },
	innerX: number,
	innerY: number,
	innerW: number,
	innerH: number,
	axisIsX: boolean
): boolean
	--[[ IT REPORTS WHETHER IT FILED (Plan C, T14). `stack.arrange`'s replay must
		re-file a containment finding about a CLEAN child — the finding carries
		`filedBy = parentId` and `solver`'s diagnostic replay drops any previous copy
		whose filer was walked, which the replaying container always is — and the
		cheapest way to know whether that re-file is owed at all is for the pass that
		files to say so. Every caller that does not care ignores it, which is every
		caller but one: a function returning a value where `-> ()` is declared is
		still a subtype of it. ]]
	if ctx.hiddenDepth ~= 0 then
		return false
	end
	local near = if axisIsX then innerX - rect.x else innerY - rect.y
	local far = if axisIsX then (rect.x + rect.w) - (innerX + innerW) else (rect.y + rect.h) - (innerY + innerH)
	if near <= 0.5 and far <= 0.5 then
		return false
	end
	if placementAudit.routesOverflow(node) then
		return false
	end
	--[[ THE PARENT MUST BE UNABLE TO GROW, and the answer comes from `axisAbsorbs`
		above rather than from a second reading of the resolver — a `hug` or
		`content` parent that ends up too small has a different story (its own
		parent squeezed it) and the measure-side findings already tell it. The
		parent's own rect IS its resolved extent by the time it is placing children,
		so the "bounded" arm of that predicate is answered by the box itself. ]]
	local wD, hD = dim(node, "w"), dim(node, "h")
	local absorbs = if axisIsX then axisAbsorbs(wD, innerW, hD, innerH) else axisAbsorbs(hD, innerH, wD, innerW)
	if not absorbs then
		return false
	end
	local found = placementAudit.containment(node, child, rect, innerX, innerY, innerW, innerH, axisIsX)
	if found == nil then
		return false
	end
	for _, finding in found do
		table.insert(ctx.diagnostics, finding)
	end
	return true
end

return arrange_reports
