--!strict
--[[ expand_plate — THE EXPAND PLATE'S OWN CHROME, DECLARED ONCE.

	Public interface: `PADDING` (the plate's four inset token NAMES, uniform),
	`CLOSE_DISC` / `CLOSE_INSET` (the disc's own metric and its inset from the
	panel's corner), `SHEET_PADDING` (the sheet twin's, which has no straddle),
	and the three resolutions against a live ThemeSnapshot — `insetX(metrics)`,
	`straddleX(metrics)` and `discHalf(metrics)` — plus `r18Clearance(metrics)`,
	the guarantee below stated as two comparable distances.
	Depends on `../themes/snapshot` and on nothing else.

	WHY IT IS ITS OWN FILE — AND IT IS NOT A SIZE SPLIT. Three layers need the
	same numbers and none of them may derive them privately:

	  · `src/blueprint.luau` BUILDS the plate and spends the tokens as a real
	    `padding` and `margin` on the node it returns;
	  · `src/layout/solver.luau` RESOLVES them, because it is the one place that
	    holds both the composition seam and the live snapshot, and hands the px
	    across on the resolve context;
	  · `src/layout/composition.luau` SPENDS the px, taking the plate's own
	    insets out of the cap before it measures form 1 against it, and carrying
	    the one number the declaration cannot spell back out on the plate record.

	THE DEFECT THAT MADE IT ONE FILE (director round 5, then round 6). `plate.w`
	measured form 1 against `viewport - 2*gutter` and the panel that wrapped it
	was wider than that answer by its own chrome — so a form whose natural width
	landed within the chrome of the cap produced a panel wider than the allowance
	it was chosen against, and near the top of the band wider than the viewport.

	IT REACHES THE COMPOSITION HERE, AND ONLY HERE. The rule the round leaves
	behind is worth stating plainly, because it is the general one: A DERIVED SIZE
	MUST INCLUDE THE INSETS OF THE BOX IT WILL BE SPENT ON, AND THE INSETS MUST BE
	READ FROM THE PLACE THAT DECLARES THEM. Every previous version of this bug —
	three of them, in three different controls — was a second copy of an inset
	that had drifted from the first. There is no second copy here: the plate's
	padding IS `PADDING`, and the number the cap reserves IS the resolution of
	`PADDING`.

	=== OPTION B — THE CORNER DISC ON SYMMETRIC PADDING (director choice,
	    2026-08-21; `task-plate-design-spec.md`) ===

	The plate reserved the disc's own metric as its RIGHT padding while its left
	was `space.s`, and then pushed the disc `space.m` outside the box on both
	axes. Measured on a phone (360x691): a 36px dead band trailed the content and
	the disc floated above-right of the box it belongs to — the eye read a panel
	bigger than its content plus a satellite. Two causes, and this file is where
	both of them were written: the close's RESERVATION participated in content
	flow, and the straddle (16) was unrelated to the disc's size (36), so the disc
	was neither on the corner nor in the panel.

	  · THE PADDING IS UNIFORM. One token on all four sides, so the content sits
	    dead centre of its own frame and no side is a reservation for chrome.
	  · THE STRADDLE IS THE DISC'S OWN HALF, PLUS THE DISC'S INSET. The disc's
	    centre offset from the panel's top-trailing corner is `CLOSE_INSET +
	    disc/2`; the plate's corner offset from the same corner IS that margin.
	    Equal by construction, at any theme ladder — the disc is centred ON the
	    corner it decorates rather than hovering near it.

	R18 — THE FRAMEWORK'S CHROME MAY SIT ON THE PLATE'S OWN PADDING AND NOWHERE
	ELSE — IS NOW AN INEQUALITY RATHER THAN A RESERVATION. The disc reaches
	`disc/2` inward from the plate's corner; the content box's nearest point is
	the padded corner, at `padding * sqrt(2)`. So the guarantee is

	    controlSizes.compact.height <= 2 * sqrt(2) * space.m        (36 <= 45.2)

	and it holds on the ten-foot ladder for free, because both sides scale
	together (54 <= 67.9). `r18Clearance` returns the two distances so a package
	that breaks it reddens in a named spec case instead of painting a disc over a
	word. NOTHING HERE IS A HAND LITERAL: every number above is a resolution of
	one of the two names below.

	WHY `discHalf` IS A PX NUMBER AND NOT A THIRD TOKEN NAME. The metric
	vocabulary sums names (`{ "space.xs", "space.m" }`) and negates them, but it
	cannot HALVE one — and half of a control's own size is exactly what a disc
	centred on a corner is offset by. Rather than widen that vocabulary for one
	ornament, the half is resolved HERE, against the same live snapshot the solver
	resolves the disc's size against, and carried to the declaration on the plate
	record beside `max` — the seam that already exists for precisely this class of
	number. The declaration then spends it as `{ CLOSE_INSET, discHalf }`, so the
	inset half of the straddle stays a live token name and only the irreducible
	half is a resolved number.
]]

local themeSnapshot = require("../themes/snapshot")

local expand_plate = {}

-- the close disc is sized by NAME, so a package that thinks a compact control is
-- 48px gets a 48px disc, a 24px straddle and a 24px cap reserve with no
-- arithmetic anywhere but here
local CLOSE_DISC = "controlSizes.compact.height"
-- how far the disc's own box sits inside the panel's corner. It is what leaves
-- room for the focus ring outside the disc (4 >= the 2px ring; 6 >= 4 at
-- ten-foot), which the shipped design had none of
local CLOSE_INSET = "space.xs"
-- the plate's frame: ONE token on all four sides (Option B's balance invariant)
local PLATE_PADDING = "space.m"

expand_plate.CLOSE_DISC = CLOSE_DISC
expand_plate.CLOSE_INSET = CLOSE_INSET
expand_plate.PADDING = { top = PLATE_PADDING, right = PLATE_PADDING, bottom = PLATE_PADDING, left = PLATE_PADDING }

-- the full-width sheet twin: a sheet is edge-to-edge and has no corner to
-- straddle, so the disc sits INSIDE its top-trailing padding and the right inset
-- is the disc's own metric — the one reservation Option B keeps, because there
-- is no half-out to take its place (design spec, Option B "Sheet")
expand_plate.SHEET_PADDING = { top = "space.m", right = CLOSE_DISC, bottom = "space.m", left = "space.m" }

--[[ THE PLATE'S OWN HORIZONTAL INSETS in px at this snapshot's scale: what the
	content cap has to give back before form 1 is measured against it.

	`nil` from `resolveNumber` means the snapshot does not carry that metric at
	all, and 0 is the right reading of that: it is what a pure test means when it
	says nothing, and it degrades to exactly the arithmetic that shipped before
	this module existed rather than to a mystery offset. ]]
function expand_plate.insetX(metrics: any): number
	local left = themeSnapshot.resolveNumber(metrics, expand_plate.PADDING.left) or 0
	local right = themeSnapshot.resolveNumber(metrics, expand_plate.PADDING.right) or 0
	return left + right
end

-- HALF THE DISC — the one number in this design that the metric vocabulary
-- cannot spell, resolved here and carried to the declaration on the plate record
function expand_plate.discHalf(metrics: any): number
	return (themeSnapshot.resolveNumber(metrics, CLOSE_DISC) or 0) / 2
end

--[[ THE MARGIN THE PLATE SITS INSIDE THE PANEL BY, on the two straddled sides.
	OUTSIDE the plate's box: the panel is the box plus this, which is what keeps
	the disc inside the surface box the anchored placement's safe-area clamp
	knows. The cap one level up subtracts it for the same reason. ]]
function expand_plate.straddleX(metrics: any): number
	return (themeSnapshot.resolveNumber(metrics, CLOSE_INSET) or 0) + expand_plate.discHalf(metrics)
end

--[[ THE R18 GUARANTEE AS TWO DISTANCES: how far the content box's nearest corner
	is from the plate's corner, and how far the disc reaches in from it. The first
	must exceed the second, and a spec case asserts it for every shipped package
	so a token change that breaks it goes red instead of painting a disc over a
	word. ]]
function expand_plate.r18Clearance(metrics: any): (number, number)
	local pad = themeSnapshot.resolveNumber(metrics, expand_plate.PADDING.top) or 0
	return pad * math.sqrt(2), expand_plate.discHalf(metrics)
end

return expand_plate
