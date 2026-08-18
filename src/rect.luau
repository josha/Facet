--!strict
--[[ RECTANGLE ALGEBRA, ONCE (reuse audit REUSE-4, REUSE-39).

	Overlap, containment, point-in-rect, equality and rounding had fifteen-plus
	bodies across `render/`, `layout/`, `present/`, `input/` and `controls/`, in
	FOUR different epsilons and TWO incompatible edge conventions. The epsilons are
	real decisions and stay at the call sites — this module takes them as
	arguments. The conventions are not: they were an accident, and this module
	gives each of them a name so a caller has to say which one it means.

	THE TWO POINT-IN CONVENTIONS, AND WHY THERE IS NO `contains(r, x, y)`.
	`src/input/drag_session.luau` documents why HALF-OPEN `[x, x+w)` is right for
	tiled drop targets: a point on a shared edge belongs to exactly one of two
	adjacent rects, so a plane of tiles partitions with no double-hit.
	`src/present/modal_zones.luau` uses CLOSED `[x, x+w]` and documents nothing —
	a tap exactly on a shared edge is Zone A for the modal test and a miss for the
	drop test. Exporting one `contains` would silently pick a winner for six call
	sites that never discussed it, so both ship with names that say what they do.

	`src/render/surface_overlap.luau` says of its own loop: "This is ADR-0025's
	collision loop with regions swapped for surfaces — same arithmetic, same
	`{ a, b, dx, dy }` row, same 'touching is not overlapping' epsilon of zero".
	ADR-0025's loop is `composition.luau`, which uses an epsilon of 0.5. Both are
	defensible; what was not defensible is that neither could see the other.

	NO REQUIRES, ON PURPOSE — the `src/spec_guard.luau` rule. `render/` may reach
	it without depending on `layout/`, and `input/` without depending on either.

	PERF: `src/layout/solver.luau:2064` records that a per-call allocation on the
	measure path is a bench regression this repository has already paid for once.
	Nothing here allocates except `round`, which returns a new rect because that is
	what its callers want; every predicate is scalar arithmetic and every hot
	caller binds it to a module-level local.
]]

export type Rect = { x: number, y: number, w: number, h: number }

local rect = {}

--[[ The overlap extents of two rects, per axis. Positive on both axes means a
	real intersection; zero or negative on either means they miss. Returning the
	two numbers rather than a boolean is what lets a caller apply its own epsilon
	AND report the depth, which is what every collision report in this repository
	actually prints. ]]
function rect.intersection(a: Rect, b: Rect): (number, number)
	return math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x), math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
end

--[[ Do two rects share area? `epsilon` is how much overlap does not count, and
	it defaults to 0 — "touching is not overlapping", because an intersection has
	to have area. Pass 0.5 to forgive a half-pixel of rounding
	(`layout/composition.luau`), or 1 to forgive a whole one
	(`layout/text_audit.luau`). ]]
function rect.overlaps(a: Rect, b: Rect, epsilon: number?): boolean
	local dx, dy = rect.intersection(a, b)
	local e = epsilon or 0
	return dx > e and dy > e
end

--[[ Is `inner` entirely within `outer`? `epsilon` is the slack allowed on every
	edge and defaults to 0 (exact). `render/renderer.luau` passes its
	`CLIP_EPSILON` of 0.5 so a child that rounds half a pixel past its clip parent
	is not reported as clipped. ]]
function rect.contains(outer: Rect, inner: Rect, epsilon: number?): boolean
	local e = epsilon or 0
	return outer.x - e <= inner.x
		and outer.y - e <= inner.y
		and outer.x + outer.w + e >= inner.x + inner.w
		and outer.y + outer.h + e >= inner.y + inner.h
end

-- CLOSED `[x, x+w] × [y, y+h]`: a point exactly on any edge is INSIDE. Use for a
-- forgiveness ring or a hit test where a boundary pixel should count.
function rect.containsClosed(r: Rect, x: number, y: number): boolean
	return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

-- HALF-OPEN `[x, x+w) × [y, y+h)`: a point on the right/bottom edge belongs to
-- the NEXT adjacent rect. Use whenever rects tile a plane and exactly one of them
-- must win — drop targets, autoscroll bands, drag registries.
function rect.containsHalfOpen(r: Rect, x: number, y: number): boolean
	return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

--[[ Field-for-field equality of two FLAT tables, refusing anything nested. The
	geometry facts a surface re-solves on are flat records, and a rebuilt-outer /
	reused-inner shape would otherwise report a false "unchanged" and the consumer
	would go silently deaf to a real move — so a table-valued field is REFUSED
	rather than compared by identity. Both directions are walked, so a key present
	on one side only is a change.

	Two copies, one across a layer boundary: `src/render/renderer.luau`'s
	`sameGeometryValue` (which gates the geometry re-solve) and
	`src/controls/selection_indicator.luau`'s `sameGeometry` (exported as
	`selection_indicator.sameGeometry`), whose comment already said it was
	"renderer.luau's `sameGeometryValue`, kept field-for-field". Kept
	field-for-field is what a shared owner is for. ]]
function rect.sameFlatValue(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		-- a nested fact is refused, never half-compared
		if type(v) == "table" then
			return false
		end
		if b[k] ~= v then
			return false
		end
	end
	for k, v in b do
		if a[k] ~= v then
			return false
		end
	end
	return true
end

--[[ Field-for-field equality, nil-tolerant on both sides. `nil == nil` is equal
	(a node that had no rect and still has none did not move); one nil is not. ]]
function rect.equal(a: Rect?, b: Rect?): boolean
	if a == nil or b == nil then
		return a == nil and b == nil
	end
	return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

-- The centre point. Tolerates a rect with no `w`/`h` (treated as zero), which is
-- what the drag registry's aim arithmetic wants from a not-yet-measured target.
function rect.centre(r: Rect): (number, number)
	return r.x + (r.w or 0) / 2, r.y + (r.h or 0) / 2
end

--[[ Snap every edge to a whole pixel with the layout code's own rule
	(`floor(v + 0.5)`, which is `num.roundPx`). Rounds the FOUR FIELDS, not the
	position and size independently — so a rect whose right edge lands on x.5 keeps
	its right edge, and two participants cannot each take half a pixel. ]]
function rect.round(r: Rect): Rect
	return {
		x = math.floor(r.x + 0.5),
		y = math.floor(r.y + 0.5),
		w = math.floor(r.w + 0.5),
		h = math.floor(r.h + 0.5),
	}
end

return rect
