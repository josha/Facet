--!strict
-- Rating: a small run of glyphs that reads as ONE value, and behaves like one.
-- (director round 10, 2026-07-26: "I don't think the rating should render
-- individual buttons for the stars. We probably want a custom rating control.")
--
-- WHY THIS EXISTS AS A CONTROL AND NOT AS FIVE BUTTONS
--
-- Five buttons is the obvious spelling and it is wrong on all three axes at
-- once, which is what the device captures showed:
--
--   * PAINT — a Button is a `control` to every theme, so each star wore a
--     plate. Under Glossy Touch a rating was five glossy PILLS; under Glossy
--     Mobile, whose control recipe is a raised SHADOW, the five shadows
--     overlapped into a smeared dark band behind the row. (The `plain` opt-out
--     landed alongside this control and stops a theme painting a node whose
--     author asked for no surface — but a rating should not have to opt out of
--     being a button in the first place, because it is not five buttons.)
--   * INPUT — five focus stops for one number. A gamepad user pressed Right
--     four times to cross one cell, and the 44px effective-target floor the
--     Button contract enforces put five overlapping hit expanders inside a
--     110px cell.
--   * SEMANTICS — "star 4" is not a thing a player does. "Rate this 4" is.
--     Five activation handlers all writing one signal is one verb wearing five
--     costumes, and nothing could read the control's value as a value.
--
-- THREE AXES (affordance matrix §A; UI-PARADIGM-001..003):
--   1. UI (layout)   — an HStack of `count` glyph Texts under a single Grip.
--                      A value change repaints exactly `count` labels: the
--                      glyphs are memos over the value, so nothing remounts and
--                      the row a rating sits in is never rebuilt.
--   2. INPUT (reach) — pointer/touch tap-to-set anywhere on the strip, plus
--                      press-and-drag to scrub (drag past the leading edge
--                      clears to zero when `allowZero`); keyboard and gamepad
--                      reach the same arithmetic through the focus-gated Adjust
--                      verb, which is ONE focus stop for the whole control.
--   3. PARADIGM      — pointer: tap or scrub; touch: the same, against the
--                      Grip's declared 44px floor; keyboard: focus ring then
--                      Adjust (Comma/Period); gamepad: focus then Adjust
--                      (L1/R1), bound only while focus is inside this control
--                      so a screen with a Rating never shadows gameplay bumpers.
--      hotSwitch     — a Rating DOES hold in-flight state (a live scrub). The
--                      decision matches Slider's: losing the pointer class
--                      mid-scrub CANCELS back to the pre-scrub value, so a
--                      half-finished drag never commits a rating nobody chose.
--
-- OWNERSHIP: `value` is the CALLER's settable Signal. The control never creates
-- it, because a rating outlives the row that shows it.
--
-- ===== WHERE THE BODY WENT (director ruling 2026-08-16) =====================
-- Everything above is unchanged and is still this control's constitution — it is
-- the argument that made a Rating a control, and it is why `newLevelPicker`
-- exists in the shape it does. What moved is the CODE: a rating turned out to be
-- one point in a family (a caller-chosen `count`, a segment painted as a glyph,
-- a bar or an image, and a tint per half), so the body is
-- `src/controls/level_picker.luau` and this file is the PRESET —
-- `count = 5`, `segment = "glyph"`, the star pair.
--
-- A preset must be the SAME control, not a copy of it, so nothing below
-- re-implements anything: this file owns its own closed spec (including
-- `starSize`, which the level picker spells `segmentSize`), its own dump schema,
-- and the node-ID vocabulary its callers already read (`<id>/Stars/Star{n}`,
-- `<id>/Strip`). Everything else is `level_picker.compose`.

local level_picker = require("./level_picker")
local specGuard = require("../spec_guard")

local rating = {}

-- THEME METRICS, NOT LITERALS (ADR-0019 §2, and `check_theme_drift` enforces
-- it). A star is an icon, so it draws on the icon ladder and resizes with the
-- package; the run's gap is the package's smallest step. Deliberately NO new
-- `controls.rating.*` metric section: adding one to the neutral DEFINITION would
-- move every derived package's content stamp and invalidate stored capture
-- evidence, for values the existing ladders already name correctly.
--
-- SMALL, not medium (measured across all nine shipped packages 2026-07-27). A
-- rating is FIVE of these side by side, so the rung that is right for one icon is
-- wrong for a row of them: at `medium` the strip measured 164px under Glossy
-- Touch and 176px under Pixel Quest and Fantasy Ornate — all of which overrun the
-- 132px column a table gives it, and the ratings ran off the end of their cells.
-- At `small` the widest is 124px and every package fits. A star in a list row is
-- a small icon; `starSize` is there for the caller who wants a hero-sized one.
local STAR_SIZE_ROLE = "small"

-- THE GLYPHS. Not from `ICON_FALLBACK_GLYPHS`: that table is ASCII by
-- construction because it is the answer for names a package declined to draw,
-- and `*`/`-` is not a star rating. These are the same judgement TextInput's
-- clear `×` (U+00D7) is — a BMP character confirmed to draw on a real device in
-- the fonts this library ships against, chosen by the control rather than
-- resolved through the theme.
--
-- A package with an exotic face (a pixel font, a display face) can hand the
-- control its own pair through `spec.glyphs` rather than gamble on coverage.
rating.FILLED = "★"
rating.EMPTY = "☆"

export type Spec = {
	id: string?,
	value: any, -- owner-held Signal<number>
	count: number?, -- how many glyphs; default 5
	-- may the value go to zero? Default true (an unrated item is a real state).
	-- With `allowZero = false` the floor is 1 and a scrub off the leading edge
	-- stops there instead of clearing.
	allowZero: boolean?,
	enabled: any?, -- boolean | Readable<boolean>
	-- a display-only rating (an average, another player's score): it paints, it
	-- is not focusable, and no input class can change it
	readOnly: boolean?,
	glyphs: { filled: string, empty: string }?,
	-- which `iconSizes` rung a star draws at. Default "small", because a rating
	-- is a ROW of icons and the rung that suits one suits five badly (see
	-- STAR_SIZE_ROLE). "medium"/"large" for a hero rating with room around it.
	starSize: ("small" | "medium" | "large")?,
	-- the live environment, so the run can space itself for the input paradigm
	-- (see the gap note below). Optional: without one the control takes the
	-- POINTER spacing, which is the tighter of the two and therefore the one that
	-- cannot overrun a cell sized for the other.
	env: any?,
	onChange: ((value: number) -> ())?,
}

-- CLOSED SPEC (constitution §4). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local RATING_KEYS = specGuard.keySet({
	"allowZero",
	"count",
	"enabled",
	"env",
	"glyphs",
	"id",
	"onChange",
	"readOnly",
	"starSize",
	"value",
})

function rating.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newRating", spec, RATING_KEYS, "spec")
	local id = spec.id or "Rating"
	local count = if spec.count ~= nil then spec.count else 5
	level_picker.validate("newRating", id, spec.value, count)

	-- ONE RULE, BOTH ENTRIES: a rating is a level picker, so a `count` too high to
	-- draw as distinct marks is diagnosed here by exactly the arithmetic that
	-- diagnoses it there — never a second copy that could drift.
	local diagnostics: { string } = {}
	level_picker.diagnoseCount("newRating", id, count, diagnostics)

	local api, facts = level_picker.compose(Facet, core, {
		constructor = "newRating",
		-- THE NODE NAMES ARE PART OF THE PRESET, not decoration: `Stars/Star{n}`
		-- and `Strip` are read by `tests/rating.spec.luau`,
		-- `tests/traversal_order.spec.luau` and `tests/examples_gallery.spec.luau`
		-- (through the shipped playlist), so renaming them would be a migration
		-- for every consumer of a control whose behaviour did not change.
		names = { run = "Stars", mark = "Star" },
		id = id,
		value = spec.value,
		count = count,
		minValue = if spec.allowZero == false then 1 else 0,
		segment = "glyph",
		-- `starSize` is this control's spelling of `segmentSize` and stays exactly
		-- what it was — same three rungs, same default, same refusal naming the key
		-- the caller actually wrote.
		sizeRole = level_picker.sizeRole("newRating", id, "starSize", spec.starSize or STAR_SIZE_ROLE),
		glyphs = if spec.glyphs ~= nil then spec.glyphs else { filled = rating.FILLED, empty = rating.EMPTY },
		images = nil,
		-- A RATING CARRIES NO TINT, and that is a preservation decision rather than
		-- an omission: a star already says which state it is in, and giving the
		-- filled half a default colour would repaint every rating this framework
		-- ships. A caller who wants a coloured run uses `newLevelPicker`.
		tint = {},
		-- ...AND NO 44px FLOOR, for the same reason. `newRating` ships today
		-- without one and its strip sits inside a table row in the shipped playlist
		-- tutorial; declaring the floor here would grow every rated row of a
		-- shipped example, which is a product change and not a refactor. Recorded
		-- as owed rather than smuggled in — `newLevelPicker` declares it from the
		-- start, so no NEW caller inherits the gap.
		targetFloor = false,
		readOnly = spec.readOnly == true,
		enabled = spec.enabled,
		env = spec.env,
		onChange = spec.onChange,
		diagnostics = diagnostics,
	})

	-- THE SCHEMA STAYS `/1`, and that is a claim about the KEYS rather than about
	-- how much code moved. Every key this dump carried before the generalization
	-- carries the exact value it carried before — `id`, `value`, `count`, `min`,
	-- `readOnly`, `enabled`, `semanticText`, `rootPath` — and the two additions
	-- (`segment`, always `"glyph"` here, and `diagnostics`) are purely additive.
	-- That is the same rule `newProgressView` followed when `indeterminate`
	-- landed, and it is the only thing a schema version is for: a consumer reading
	-- any key it read yesterday reads the same thing today.
	function api.dump()
		local out = facts()
		out.schema = "facet-rating-dump/1"
		return out
	end

	return api
end

return rating
