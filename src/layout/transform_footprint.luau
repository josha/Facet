--!strict
--[[ transform_footprint — the reserved-box formula for a scaled/rotated node
	(framework-gaps-phase2 gap 33, audit-marked "teaches-wrong 12").

	`scale`/`rotation` are PAINT-ONLY: the solver reserves a node's
	UNSCALED box and the engine draws the transformed one, so a container
	carrying an authored `scale`/`rotation` overflows its own slot and a parent
	that wants to avoid a spillover has to reserve the PAINTED footprint itself
	— a plain sibling box the SIZE of the transformed output, sitting OUTSIDE
	the node that scales (a wrapper that scales WITH its contents reserves
	nothing).

	Found on a device 2026-08-17 (`docs/reference/api.md`'s `scale` row): a
	100x70 box at scale 1.5 / rotation 30 painted 182.40 x 165.93 into its
	100x70 slot and spilled onto its neighbours.
	`examples/gallery/scenarios/nested_compositing.luau` transcribed the fix by
	hand under a comment naming this exact function as the owed API:

		"PROBE-EXEMPT BEGIN: TRANSCRIBED TRIGONOMETRY — a workaround, not a
		lesson... The framework owes a reserved-footprint API here (purity
		audit teaches-wrong §12); until it has one, copy this at your own risk
		rather than as the house style."

	This is that API — pure geometry, no engine, no theme, no node — so a
	future caller computes the reservation instead of copying the formula (and
	the `FOOTPRINT_SLACK` fudge constant that copy needed to remember on top of
	it stays a caller-side buffer choice, not something this function bakes
	in). ]]

local transform_footprint = {}

--[[ The axis-aligned bounding box of a `w x h` rectangle scaled uniformly by
	`scale` and rotated `deg` degrees about its own centre, ROUNDED UP (a
	reservation that rounds down clips a fraction of a pixel off an edge —
	`api.md`'s own worked example: the exact height at scale 1.5/30deg is
	165.93, and reserving `166` centres it with 0.03px to spare on a side).

	`w*s*|cos d| + h*s*|sin d|` by `w*s*|sin d| + h*s*|cos d|` — the formula
	`api.md`'s `scale` row documents in prose, transcribed here once. ]]
function transform_footprint.transformFootprint(w: number, h: number, scale: number, deg: number): (number, number)
	local r = math.rad(deg)
	local sw, sh = w * scale, h * scale
	local c, s = math.abs(math.cos(r)), math.abs(math.sin(r))
	return math.ceil(sw * c + sh * s), math.ceil(sw * s + sh * c)
end

return transform_footprint
