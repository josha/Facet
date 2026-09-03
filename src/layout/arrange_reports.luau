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

	WHY THE THREE MESSAGES SIT TOGETHER. They are the reports a node can only make
	about ITS OWN BOX once the box is resolved — a theme too big for the control, an
	icon floor that was refused, a content box padding emptied, and a child holding
	a placement prop this parent will never read. All four are gated on
	`ctx.hiddenDepth == 0` (a losing ViewThatFits candidate does not shout) and all
	four are replayed by the reuse path, which is the pair of properties that makes
	them one block rather than four. ]]
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

return arrange_reports
