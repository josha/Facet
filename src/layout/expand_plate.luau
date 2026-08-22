--!strict
--[[ expand_plate — THE EXPAND PLATE'S OWN CHROME, DECLARED ONCE.

	Public interface: `PADDING` (the plate's four inset token NAMES), `STRADDLE`
	(the margin the close disc sits half-out on), `SHEET_PADDING` (the sheet
	twin's, which has no straddle), and `insetX(metrics)` / `straddleX(metrics)` —
	the two horizontal halves in px, resolved against a live ThemeSnapshot.
	Depends on `../themes/snapshot` and on nothing else.

	WHY IT IS ITS OWN FILE — AND IT IS NOT A SIZE SPLIT. Three layers need the
	same numbers and none of them may derive them privately:

	  · `src/blueprint.luau` BUILDS the plate and spends the tokens as a real
	    `padding` and `margin` on the node it returns;
	  · `src/layout/solver.luau` RESOLVES them, because it is the one place that
	    holds both the composition seam and the live snapshot, and hands the px
	    across as `resolveCtx.expandPlateChrome`;
	  · `src/layout/composition.luau` SPENDS the px, taking the plate's own
	    insets out of the cap before it measures form 1 against it.

	THE DEFECT THAT MADE IT ONE FILE (director round 5, then round 6). `plate.w`
	measured form 1 against `viewport - 2*gutter` and the panel that wrapped it
	was wider than that answer by its own chrome — so a form whose natural width
	landed within the chrome of the cap produced a panel wider than the allowance
	it was chosen against, and near the top of the band wider than the viewport.
	Round 5 fixed the inner half by making the plate HUG (a padded box's declared
	width is its OUTER width, so writing a content number onto one is the same
	defect one level down) and CONTESTED the rest, because the number that closes
	it could not reach the composition.

	IT REACHES IT HERE, AND ONLY HERE. The rule the round leaves behind is worth
	stating plainly, because it is the general one: A DERIVED SIZE MUST INCLUDE
	THE INSETS OF THE BOX IT WILL BE SPENT ON, AND THE INSETS MUST BE READ FROM
	THE PLACE THAT DECLARES THEM. Every previous version of this bug — three of
	them, in three different controls — was a second copy of an inset that had
	drifted from the first. There is no second copy here: the plate's padding IS
	`PADDING`, and the number the cap reserves IS the resolution of `PADDING`.

	R18 IS PRESERVED BY CONSTRUCTION and that is why the right inset is the disc's
	own metric rather than a spacing step: the content box's right edge is
	`panel - straddle - disc` and the disc's left edge is `panel - disc`, so the
	difference is the straddle and is never negative, at any theme ladder.
]]

local themeSnapshot = require("../themes/snapshot")

local expand_plate = {}

-- the close disc is sized by NAME, so a package that thinks a compact control is
-- 48px gets a 48px disc and a 48px reserve with no arithmetic anywhere
local CLOSE_DISC = "controlSizes.compact.height"

-- the anchored plate: `space.s` on three sides, the disc's own metric on the
-- right (the reserve R18 spends), and the straddle as a MARGIN rather than an
-- offset on the disc — the panel's box grows by it, so the anchored placement's
-- safe-area clamp is already clamping a box that CONTAINS the disc
expand_plate.PADDING = { top = "space.s", right = CLOSE_DISC, bottom = "space.s", left = "space.s" }
expand_plate.STRADDLE = "space.m"

-- the full-width sheet twin: roomier insets, the same disc reserve, and NO
-- straddle, because a sheet is edge-to-edge and has no corner to overlap
expand_plate.SHEET_PADDING = { top = "space.m", right = CLOSE_DISC, bottom = "space.m", left = "space.m" }

--[[ THE TWO HALVES OF THE ANCHORED PLATE'S HORIZONTAL CHROME, in px at this
	snapshot's scale — and they are two numbers because they sit on OPPOSITE SIDES
	of the box the caller declares.

	  `insetX`     the plate's own left + right padding (the right one is the disc
	               reserve). INSIDE the plate's box: the content is the box minus
	               this.
	  `straddleX`  the margin the disc sits half-out on. OUTSIDE the plate's box:
	               the panel is the box plus this.

	Collapsing them into one "chrome" number is the bug one level up, and it was
	written that way first: the plate's declared width is an OUTER width, so a cap
	that had already subtracted the straddle would under-size the box by exactly
	the straddle, and a cap that had not would over-size the panel by exactly the
	straddle. Which of the two you get depends on whether the form hugs or fills,
	which is the reader's business and not this module's.

	`nil` from `resolveNumber` means the snapshot does not carry that metric at
	all, and 0 is the right reading of that: it is what a pure test means when it
	says nothing, and it degrades to exactly the arithmetic that shipped before
	this module existed rather than to a mystery offset.
]]
function expand_plate.insetX(metrics: any): number
	local left = themeSnapshot.resolveNumber(metrics, expand_plate.PADDING.left) or 0
	local right = themeSnapshot.resolveNumber(metrics, expand_plate.PADDING.right) or 0
	return left + right
end

function expand_plate.straddleX(metrics: any): number
	return themeSnapshot.resolveNumber(metrics, expand_plate.STRADDLE) or 0
end

return expand_plate
