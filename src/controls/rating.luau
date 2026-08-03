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

local controlContract = require("./contract")
local contribution = require("../input/contribution")
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

-- CLOSED SPEC (constitution §4; ARCH-1). Exactly the fields this control
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

function rating.build(LuauUI: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newRating", spec, RATING_KEYS, "spec")
	local UI = LuauUI.UI
	local id = spec.id or "Rating"
	local scope = core:scope("rating-" .. tostring(id))
	local value = spec.value
	-- a read-only Memo has kind "memo" and a :set that asserts, so a bare
	-- "settable" duck-type check would pass and then blow up on the first tap —
	-- reject it at BUILD, exactly as Stepper and Slider do
	if type(value) ~= "table" or (value :: any).kind ~= "signal" then
		error(
			`LuauUI newRating('{id}'): \`value\` must be a SETTABLE Signal<number> the caller owns `
				.. `(the control never creates it, because the value must outlive the control)`,
			0
		)
	end
	local count = spec.count or 5
	if type(count) ~= "number" or count < 1 or count % 1 ~= 0 then
		error(`LuauUI newRating('{id}'): \`count\` must be a whole number >= 1 (got {tostring(spec.count)})`, 0)
	end
	local minValue = if spec.allowZero == false then 1 else 0
	local filled = if spec.glyphs ~= nil then spec.glyphs.filled else rating.FILLED
	local empty = if spec.glyphs ~= nil then spec.glyphs.empty else rating.EMPTY
	local readOnly = spec.readOnly == true
	local starRole = spec.starSize or STAR_SIZE_ROLE
	if starRole ~= "small" and starRole ~= "medium" and starRole ~= "large" then
		error(`LuauUI newRating('{id}'): starSize must be small | medium | large (got '{tostring(spec.starSize)}')`, 0)
	end
	-- a theme METRIC name, resolved on every solve, so a package that resizes its
	-- icon ladder resizes the rating with no rebuild
	local starSize = `iconSizes.{starRole}`

	-- WIDER FOR A FINGER THAN FOR A CURSOR (director, 2026-07-27: "if we're on a
	-- touch input, part of the paradigm should be slightly wider spacing for touch
	-- targets vs. what we can do with a pointer").
	--
	-- The run is ONE drag target, so the gap is what makes an individual star
	-- reachable: a fingertip needs more room between marks than a cursor, which
	-- lands where it is aimed. `iconRunGap` is derived from the package's own
	-- `iconSizes` (snapshot.luau), so this scales with whatever the theme sized
	-- its icons at instead of borrowing the page's spacing ladder — Compact
	-- Pointer's `xs` is 2px against a 12px star, a 17% gap, which is exactly the
	-- "too tight" the report named.
	--
	-- It is a METRIC NAME and `gap` is reactive, so switching input class is a
	-- RE-SOLVE and never a rebuild: the strip re-spaces under a live hot-switch
	-- with the value and the scrub state intact.
	local starGap = if spec.env ~= nil
		then scope:own(core:memo(function(use)
			local classes = use(spec.env:get("interactionClasses"))
			return `iconRunGap.{starRole}.{if classes.touch == true then "touch" else "pointer"}`
		end))
		else `iconRunGap.{starRole}.pointer`

	-- `readOnly` is a Rating-only refusal ON TOP of the contract's reading of
	-- `enabled`: a read-only rating still paints and still takes a focus stop, it
	-- just never changes
	local function isEnabled(): boolean
		return not readOnly and controlContract.enabledNow(spec.enabled)
	end

	-- THE ONE MUTATION SITE: every input class routes here, so "what a rating
	-- may be" is decided once instead of once per affordance.
	local function apply(next_: number): boolean
		if not isEnabled() then
			return false
		end
		local resolved = math.clamp(math.floor(next_ + 0.5), minValue, count)
		if resolved == value:get() then
			return false
		end
		value:set(resolved)
		if spec.onChange ~= nil then
			spec.onChange(resolved)
		end
		return true
	end

	-- pointer set/scrub: one ratio against the strip's own solved rect, so the
	-- same handler serves a tap and a drag and neither needs a recognizer
	local scrubFrom: number? = nil
	local function setFromPoint(path: string, pos: any, rectOf: (string) -> any): boolean
		local rect = rectOf(path)
		if rect == nil or rect.w <= 0 then
			return false
		end
		local ratio = (pos.x - rect.x) / rect.w
		return apply(math.clamp(math.ceil(ratio * count), minValue, count))
	end

	local glyphs = {}
	for i = 1, count do
		local index = i
		glyphs[i] = UI.Text({
			id = `Star{index}`,
			-- ONE MEMO PER GLYPH over the shared value: a rating change repaints
			-- exactly `count` labels and rebuilds nothing. This is why the stars
			-- are Texts and not a single rendered string — a string would be one
			-- node but it would also be one measure, and the strip's width would
			-- twitch as the glyphs changed.
			text = scope:own(core:memo(function(use)
				return if use(value) >= index then filled else empty
			end)),
			-- THE GLYPH IS SIZED; THE BOX IS SHARED (director round 12, 2026-07-27:
			-- "in glossy touch the star spacing is so wide it overflows the row,
			-- whereas in pixel quest it's leaving extra space on the right").
			--
			-- Both complaints are one cause. A fixed box per star makes the strip's
			-- width a THEME's arithmetic — `count` icons plus gaps — while the cell
			-- it sits in is the CALLER's fixed number, and the two only agree by
			-- luck: the same 132px column overran by 12px under Glossy Touch and
			-- left 28px empty under Pixel Quest.
			--
			-- ...AND THE SHARE IS CAPPED AT THE GLYPH (director ruling 2026-07-27,
			-- superseding round 12's "it FILLS the cell"). An even share fixed the
			-- strip's outer width and left its INNER spacing to chance: the box
			-- became the caller's arithmetic while the glyph stayed the theme's, so
			-- the two diverged by whatever slack the column happened to have.
			-- Measured in the playlist's 132px rating column, the gap as a fraction
			-- of the glyph reached 0.67 under Compact Pointer — a 15px star in a
			-- 25px box, five marks that stopped reading as one rating.
			--
			-- `minMax` with a `max` resolves CONTENT (the glyph) clamped to the icon
			-- metric and then capped at the offer, which is the two behaviours in
			-- one declaration: room to spare -> the star is glyph-sized and the run
			-- groups; not enough room -> it shrinks exactly as the share did. The
			-- strip is centred in its cell (see the root) so the leftover sits on
			-- both sides rather than being dumped after the last star.
			textSize = starSize,
			textAlign = "center",
			width = { type = "minMax", max = starSize },
			-- NOT a Button, and therefore not a `control` to any theme: a star is
			-- a glyph, and the whole point of this control is that a rating wears
			-- one surface (none) rather than `count` of them.
		})
	end

	local root = UI.ZStack({
		id = id,
		-- the strip takes the box it is given (see the star's own note): `fill`
		-- here is what lets the shares below be shares OF something. In a
		-- content-sized parent a `fill` measures as its own content, so a
		-- standalone rating still hugs its glyphs rather than stretching.
		width = { type = "fill", weight = 1 },
		children = {
			UI.HStack({
				id = "Stars",
				gap = starGap,
				-- THE STRIP GROUPS, AND IS CAPPED (director ruling 2026-07-27,
				-- superseding round 12's "it FILLS the cell"). Round 12 made each
				-- star an even SHARE of the cell, which fixed the strip's outer
				-- width and left its inner spacing to chance: the box became the
				-- caller's arithmetic while the glyph stayed the theme's. Measured
				-- in the playlist's 132px rating column, the gap as a fraction of
				-- the glyph ran to 0.67 under Compact Pointer — a 15px star in a
				-- 25px box, five marks that stopped reading as one rating.
				--
				-- `hug` = the run's own width, CAPPED at the cell. It can measure
				-- its children now that each star is glyph-sized; with the old
				-- `fill` stars it collapsed to just the gaps, because a `fill` child
				-- reports no content of its own.
				width = { type = "hug" },
				-- CENTRED IN WHATEVER COLUMN IT IS GIVEN (director, 2026-07-27).
				-- Now that the run hugs its glyphs it no longer reaches both edges
				-- of a generous cell, so where the slack goes is a visible decision:
				-- a rating pinned to the leading edge of a wide column reads as
				-- misaligned with its own header.
				--
				-- This works because the ROOT is a ZStack and `alignH` is honoured
				-- for zstack children (and grid cells) — an HStack ignores it, so
				-- putting it on this stack to move its own children would have been
				-- accepted-and-ignored. It is the hug above that gives the ZStack
				-- something narrower than the cell to centre.
				alignH = "center",
				children = glyphs,
			}),
			-- THE STRIP IS THE CONTROL. One Grip over the glyphs: one focus stop,
			-- one 44px effective target, one place pointer input lands. A
			-- read-only rating drops out of the focus ring entirely rather than
			-- offering a ring that does nothing.
			UI.Grip({
				id = "Strip",
				focusable = not readOnly,
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				onPointerDown = function(path: string, pos: any, rectOf: (string) -> any)
					scrubFrom = value:get()
					setFromPoint(path, pos, rectOf)
				end,
				onPointerMove = function(path: string, pos: any, rectOf: (string) -> any)
					setFromPoint(path, pos, rectOf)
				end,
				onPointerUp = function()
					scrubFrom = nil
				end,
				onPointerCancel = function()
					-- CANCEL, not commit (the hotSwitch decision above): put back
					-- what was there before the scrub started
					if scrubFrom ~= nil then
						apply(scrubFrom)
						scrubFrom = nil
					end
				end,
			}),
		},
	})

	local rootPath: string? = nil

	local built = contribution.attach(root, {
		-- focus-gated Adjust (ADR-0013): the strip is the adjust target, so
		-- keyboard Comma/Period and gamepad L1/R1 reach the same arithmetic while
		-- focus sits on this control — and are UNBOUND otherwise.
		adjustTargets = function(rootNode: any): { [string]: boolean }
			rootPath = rootNode.path
			local out: { [string]: boolean } = {}
			if readOnly then
				return out
			end
			local function walk(node: any)
				if node.class == "Grip" then
					out[node.path] = true
				end
				for _, child in node.children or {} do
					walk(child)
				end
			end
			walk(rootNode)
			return out
		end,
		handleAdjust = function(_path: string, direction: number): boolean
			return apply(value:get() + direction)
		end,
	})

	local api = {}
	api.blueprint = built

	-- HOT SWITCH (UI-PARADIGM-003), the same seam Slider publishes: the host
	-- tells the control its pointer class went away, and a live scrub reverts to
	-- the value the player started from. A half-finished drag must never commit.
	function api.onInteractionClassLost(class: string)
		if (class == "pointer" or class == "touch") and scrubFrom ~= nil then
			apply(scrubFrom)
			scrubFrom = nil
		end
	end

	-- the value IN ITS RANGE, so a ten-foot readout or an assistive layer never
	-- gets a bare number with no context (the B-VAL1 shape Slider/Stepper share)
	api.semanticText = scope:own(core:memo(function(use)
		return `{use(value)} of {count}`
	end))

	function api.dump()
		return {
			schema = "luauui-rating-dump/1",
			id = id,
			value = value:get(),
			count = count,
			min = minValue,
			readOnly = readOnly,
			enabled = isEnabled(),
			semanticText = api.semanticText:get(),
			rootPath = rootPath,
		}
	end

	function api.dispose()
		scope:dispose()
	end

	return api
end

return rating
