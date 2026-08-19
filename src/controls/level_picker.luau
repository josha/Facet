--!strict
-- LevelPicker: a run of `count` discrete segments that reads as ONE value, and
-- behaves like one. (director ruling 2026-08-16: generalize the shipped
-- `newRating` — a caller-chosen maximum, three ways to paint a level, and a
-- tint pair for the filled and empty halves.)
--
-- ===== WHY THIS IS ONE CONTROL AND NOT `count` BUTTONS =======================
-- The argument is `src/controls/rating.luau`'s, made there for five stars and
-- measured on real devices; read it there, because it is the reason this file
-- exists. It does not weaken when `count` becomes the caller's — it gets
-- STRICTER, on all three of its axes:
--
--   * PAINT — a Button is a `control` to every theme, so each segment would wear
--     a plate. Five glossy pills was the recorded defect; ten is worse, and a
--     `count = 20` capacity indicator would be twenty overlapping shadows. Every
--     segment here is a Text, a Box or an Image — none of which any theme skins
--     as a control (`chrome_slots.classify` returns nil for all three).
--   * INPUT — `count` focus stops for one number. A gamepad user already had to
--     press Right four times to cross one rating cell; at ten segments they
--     press it nine times, and the 44px effective-target floor would put ten
--     overlapping hit expanders inside one strip.
--   * SEMANTICS — "level 7" is not a thing a player does; "set this to 7" is.
--     `count` activation handlers all writing one signal is one verb wearing
--     `count` costumes, and nothing could read the control's value as a value.
--
-- SO THE ± BUTTONS IN THE REFERENCE SCREENSHOT ARE NOT PART OF THIS CONTROL
-- (director ruling 2026-08-16). They are separate `newStepper`s sharing the same
-- Signal, which is Apple's own composition rule for the pair: "A stepper sits
-- next to a field that displays its current value, because the stepper itself
-- doesn't display a value" (HIG, Steppers). Building them in would put two more
-- focus stops inside a control whose whole claim is that it has one, and would
-- make the ± reachable only where a level picker is — the opposite of what a
-- stepper is for. `examples/gallery/scenarios/level_picker.luau` shows the
-- composition on screen.
--
-- ===== THREE AXES (affordance matrix §A; UI-PARADIGM-001..003) ===============
--   1. UI (layout)   — a uniform `UI.Grid` of `count` marks under a single Grip.
--                      A value change repaints exactly `count` leaves: the marks
--                      are memos over the value, so nothing remounts and the row
--                      a picker sits in is never rebuilt.
--   2. INPUT (reach) — pointer/touch tap-to-set anywhere on the strip, plus
--                      press-and-drag to scrub (drag past the leading edge
--                      clears to zero when `allowZero`); keyboard and gamepad
--                      reach the same arithmetic through the focus-gated Adjust
--                      verb, which is ONE focus stop for the whole control.
--   3. PARADIGM      — pointer: tap or scrub; touch: the same, against the
--                      declared 44px floor; keyboard: focus ring then Adjust
--                      (Comma/Period); gamepad: focus then Adjust (L1/R1), bound
--                      only while focus is inside this control. At its limit the
--                      arrow goes back to navigation (ruling 9, 2026-08-14):
--                      `handleAdjust` returns false and the presenter moves the
--                      ring instead, so nothing after a maxed-out picker is
--                      unreachable on a gamepad.
--      hotSwitch     — a picker DOES hold in-flight state (a live scrub). The
--                      decision matches Slider's and Rating's: losing the
--                      pointer class mid-scrub CANCELS back to the pre-scrub
--                      value, so a half-finished drag never commits a level
--                      nobody chose.
--
-- OWNERSHIP: `value` is the CALLER's settable Signal. The control never creates
-- it, because a level outlives the row that shows it.

local controlContract = require("../class_contract")
local contribution = require("../input/contribution")
local specGuard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")

local level_picker = {}

-- ===== THE THREE SEGMENTS ===================================================
-- WHAT ONE LEVEL IS PAINTED AS. Three shapes, and the difference between them is
-- only ever the LEAF and how the run divides its offer — the value model, the
-- input story, the focus story and the diagnostics are written once, below.
--
--   bar    a tinted `UI.Box` per level. The DEFAULT, and the reference
--          screenshot's shape. It needs NO assets, so it themes and scales
--          anywhere; the marks divide the offered width, so ten of them and
--          three of them are the same declaration.
--   glyph  a `UI.Text` per level (`newRating`'s shape). The mark is content, so
--          the run hugs its glyphs and groups.
--   image  a `UI.Image` per level, for a package that ships its own art.
local SEGMENTS: { [string]: boolean } = table.freeze({ bar = true, glyph = true, image = true })
local SEGMENT_LIST = '"bar" | "glyph" | "image"'
level_picker.DEFAULT_SEGMENT = "bar"

-- THE GLYPHS, when a glyph picker names none. Not from `ICON_FALLBACK_GLYPHS`:
-- that table is ASCII by construction because it is the answer for names a
-- package declined to draw, and `*`/`-` is not a level. These are the same
-- judgement TextInput's clear `×` (U+00D7) is — BMP characters confirmed to draw
-- on a real device in the fonts this library ships against, chosen by the
-- control rather than resolved through the theme. `newRating` is the caller that
-- needs them to be exactly these two.
level_picker.GLYPH_FILLED = "★"
level_picker.GLYPH_EMPTY = "☆"

-- SMALL, not medium (measured across all nine shipped packages 2026-07-27, and
-- the measurement generalizes: a level picker is `count` marks side by side, so
-- the rung that is right for ONE icon is wrong for a row of them). At `medium`
-- the five-mark strip measured 164px under Glossy Touch and 176px under Pixel
-- Quest and Fantasy Ornate — all of which overrun the 132px column a table gives
-- it. `segmentSize` is there for the caller who wants a hero-sized run.
local DEFAULT_SIZE_ROLE = "small"
local SIZE_ROLES: { [string]: boolean } = table.freeze({ small = true, medium = true, large = true })

-- ===== THE BAR'S TWO DEFAULT TINTS ==========================================
-- A bar has no glyph and no asset, so the ONLY thing that can say "this level is
-- filled" is its colour — which is why these two exist and why `glyph`/`image`
-- have no counterpart (their mark already carries the state, and giving a star a
-- default tint would repaint every shipped rating).
--
-- Both are ROLE tints at `blend = 1`, so a package retints the whole control by
-- retinting two palette roles and nothing here names a hue. Deliberately NOT
-- `blend = 0` on one shared role: `blend = 0` is the class's identity base
-- (`sheet_model.TINT_IDENTITY`), which the framework does not infer from the
-- node's `surface` — so the empty half would paint whatever that base happens to
-- be rather than the control colour a designer can see and change. Two named
-- roles, both fully claimed, is the only spelling with no implicit half.
local DEFAULT_BAR_TINT = table.freeze({
	filled = table.freeze({ role = "accent", blend = 1 }),
	empty = table.freeze({ role = "control", blend = 1 }),
})

-- ===== THE HIGH-COUNT DIAGNOSTIC ============================================
-- Apple, HIG Gauges: "A large value range can make the segments of a discrete
-- capacity indicator too small to be useful." A DIAGNOSTIC and never a refusal —
-- the caller may have more room than a phone, and a framework that refused a
-- count it has not measured against the caller's actual box would be overruling
-- evidence it does not have.
--
-- THE NUMBER IS MEASURED, NOT PICKED, and it is deliberately NOT the round one.
-- 11 is the largest `count` at which every shipped theme package still solves
-- each `bar` segment at least as wide as the narrowest mark that package draws
-- (`iconSizes.small`), on the narrowest viewport this framework sweeps
-- (320x640), with the run spaced for TOUCH — the paradigm whose run gap is
-- wider, and therefore the one where the segments run out of room first.
--
-- Measured 2026-08-16, full-width strip at 320px:
--   glossy_touch / fantasy_ornate  small = 20, touch gap = 9  -> 11 fits (23px),
--                                  12 does not (18.4px)   <- the binding pair
--   glossy_mobile / pixel_quest / scifi_hud / classic_desktop /
--   fantasy_parchment              small = 16, touch gap = 7  -> 14
--   compact_pointer                small = 12, touch gap = 5  -> 19
-- The minimum across the eight is 11, so 11 is the threshold.
-- `tests/level_picker.spec.luau` re-derives BOTH halves from a real solve rather
-- than trusting this comment, so the number cannot quietly stop being true when
-- a package retunes its icon ladder.
--
-- The director's reference screenshot uses 10, which sits inside the threshold
-- with room to spare — and is the honest reason this warns rather than refuses.
level_picker.HIGH_COUNT = 11

export type Spec = {
	id: string?,
	value: any, -- owner-held Signal<number>
	count: number?, -- how many levels; default 5
	-- may the value go to zero? Default true (an unset level is a real state, and
	-- the reference screenshot's second picker is at zero). With
	-- `allowZero = false` the floor is 1 and a scrub off the leading edge stops
	-- there instead of clearing.
	allowZero: boolean?,
	-- what ONE level is painted as; default "bar" (see SEGMENTS)
	segment: ("bar" | "glyph" | "image")?,
	-- the glyph pair, for `segment = "glyph"` only
	glyphs: { filled: string, empty: string }?,
	-- the asset pair, REQUIRED for `segment = "image"` (an image picker with
	-- nothing to draw is an empty strip, not a default)
	images: { filled: string, empty: string }?,
	-- the continuous-colour channel, one value per half, both independently
	-- optional: omitting one leaves that half to the theme. Each is an ordinary
	-- Facet tint — `{ role = …, blend = … }` (themable) or `{ direct = … }`.
	tint: { filled: any?, empty: any? }?,
	enabled: any?, -- boolean | Readable<boolean>
	-- a display-only picker (a reported quality level, another player's setting):
	-- it paints, it is not focusable, and no input class can change it
	readOnly: boolean?,
	-- which `iconSizes` rung a segment draws at. Default "small", because a level
	-- picker is a ROW of marks and the rung that suits one suits ten badly.
	segmentSize: ("small" | "medium" | "large")?,
	-- the live environment, so the run can space itself for the input paradigm
	-- (a fingertip needs more room between marks than a cursor). Optional:
	-- without one the control takes the POINTER spacing, which is the tighter of
	-- the two and therefore the one that cannot overrun a cell sized for the other.
	env: any?,
	onChange: ((value: number) -> ())?,
}

-- CLOSED SPEC (constitution §4; ARCH-1). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op. Note
-- `starSize` is deliberately absent: it is `newRating`'s spelling, and this
-- control's is `segmentSize`, so the rename is a refusal that names the key
-- rather than a silently-defaulted size.
local LEVEL_PICKER_KEYS = specGuard.keySet({
	"allowZero",
	"count",
	"enabled",
	"env",
	"glyphs",
	"id",
	"images",
	"onChange",
	"readOnly",
	"segment",
	"segmentSize",
	"tint",
	"value",
})

--[[ THE SHARED BODY. `newRating` is a preset over this control, and a preset
	must be the SAME control rather than a copy of it — so everything below is
	written once and the two public entries differ only in what they put in
	`cfg`. The node-ID vocabulary is part of `cfg` for one reason and it is not
	cosmetic: `newRating`'s strip is `<id>/Stars/Star{n}` and `<id>/Strip` in six
	shipped spec files, the playlist tutorial and a reference app, and a preset
	that renamed its own nodes would be a migration wearing a compatibility
	shim. ]]
export type Config = {
	-- the public constructor the caller actually wrote. It names the ownership
	-- scope (a leak report has to point at a line somebody typed) and nothing
	-- else — the refusals take it as a parameter, and the DUMP SCHEMA is
	-- deliberately NOT here: each entry stamps its own onto `facts()`, so this
	-- shared body cannot renumber one control's contract by editing the other's.
	constructor: string,
	names: { run: string, mark: string },
	id: string,
	value: any,
	count: number,
	minValue: number,
	segment: string,
	sizeRole: string,
	glyphs: { filled: string, empty: string }?,
	images: { filled: string, empty: string }?,
	tint: { filled: any?, empty: any? },
	-- declare the 44px effective-target floor on the strip. TRUE for
	-- `newLevelPicker`; FALSE for `newRating`, which ships today without one and
	-- whose strip sits in a table row in a shipped tutorial — growing every rated
	-- row of a shipped example is a product change, not a refactor. Recorded as
	-- an owed follow-up rather than smuggled in here.
	targetFloor: boolean,
	readOnly: boolean,
	enabled: any?,
	env: any?,
	onChange: ((value: number) -> ())?,
	diagnostics: { string },
}

-- the two validations both public entries share, with the constructor NAME
-- passed in so every refusal says which one the caller wrote
local function validate(constructor: string, id: string, value: any, count: any)
	-- a read-only Memo has kind "memo" and a :set that asserts, so a bare
	-- "settable" duck-type check would pass and then blow up on the first tap —
	-- reject it at BUILD, exactly as Stepper and Slider do
	if type(value) ~= "table" or (value :: any).kind ~= "signal" then
		error(
			`Facet {constructor}('{id}'): \`value\` must be a SETTABLE Signal<number> the caller owns `
				.. `(the control never creates it, because the value must outlive the control)`,
			0
		)
	end
	if type(count) ~= "number" or count < 1 or count % 1 ~= 0 then
		error(`Facet {constructor}('{id}'): \`count\` must be a whole number >= 1 (got {tostring(count)})`, 0)
	end
end

-- the size rung, validated by the SPELLING the caller used (`starSize` on a
-- rating, `segmentSize` on a level picker) so the message names the key they wrote
local function sizeRole(constructor: string, id: string, key: string, requested: any): string
	local role = requested or DEFAULT_SIZE_ROLE
	if not SIZE_ROLES[role] then
		error(`Facet {constructor}('{id}'): {key} must be small | medium | large (got '{tostring(requested)}')`, 0)
	end
	return role
end

-- ONE RULE, BOTH ENTRIES (see HIGH_COUNT). Appends to `notes` rather than
-- returning, because a diagnostic list is the control's and a caller reads it
-- through `diagnostics()` / `dump().diagnostics`.
local function diagnoseCount(constructor: string, id: string, count: number, notes: { string })
	if count <= level_picker.HIGH_COUNT then
		return
	end
	table.insert(
		notes,
		`Facet {constructor}('{id}'): count = {count} is above {level_picker.HIGH_COUNT}, the largest run every `
			.. "shipped theme package still draws as a distinct segment on the narrowest viewport this framework "
			.. 'sweeps. Apple says the same of this shape (HIG, Gauges): "A large value range can make the '
			.. 'segments of a discrete capacity indicator too small to be useful." This is a diagnostic and not '
			.. "a refusal — you may have more room than a phone; check the strip on the narrowest screen you ship."
	)
end

function level_picker.compose(Facet: any, core: any, cfg: Config)
	local UI = Facet.UI
	local id = cfg.id
	-- named for the CONSTRUCTOR the caller wrote, not for the shared body: a leak
	-- report that says `newRating-Score` points at a line somebody wrote, while
	-- `level-picker-Score` points at a file they have never opened
	local scope = core:scope(`{cfg.constructor}-{id}`)
	local value = cfg.value
	local count = cfg.count
	local minValue = cfg.minValue
	local readOnly = cfg.readOnly

	-- a theme METRIC name, resolved on every solve, so a package that resizes its
	-- icon ladder resizes the picker with no rebuild
	local markSize = `iconSizes.{cfg.sizeRole}`

	-- WIDER FOR A FINGER THAN FOR A CURSOR (director, 2026-07-27). The run is ONE
	-- drag target, so the gap is what makes an individual segment reachable.
	-- `iconRunGap` is derived from the package's own `iconSizes` (snapshot.luau),
	-- so this scales with whatever the theme sized its icons at instead of
	-- borrowing the page's spacing ladder. It is a METRIC NAME and `gap` is
	-- reactive, so switching input class is a RE-SOLVE and never a rebuild: the
	-- strip re-spaces under a live hot-switch with the value and the scrub intact.
	--[[ …and the environment ARRIVES BY ITSELF when the caller did not pass one
		(ADAPT-1). The density above was `env`-gated and the key is optional, so the
		measured default on a touch phone was the POINTER run — 5px between marks
		where a finger gets 7 — on every call site that did not wire it (audit C-9).
		The surface this control was built on publishes its environment on the core
		(`src/env/surface_env.luau`), so asking costs the author nothing.

		A CONTROL WITH NO ENVIRONMENT ANYWHERE STILL BUILDS, deliberately, and this
		is the one place in this wave that does not refuse: the documented fallback
		is the TIGHTER of the two runs — "the one that cannot overrun a cell sized
		for the other" — so an unwired control is cramped, never broken, and the
		same body builds `newRating`, whose spacing the audit never measured as a
		paradigm failure. Refusing to construct a rating over 2px would be a bigger
		change than the defect. ]]
	local envForDensity = if cfg.env ~= nil then cfg.env else (surfaceEnv.find(core))
	local markGap = if envForDensity ~= nil
		then scope:own(core:memo(function(use)
			local classes = use(envForDensity:get("interactionClasses"))
			return `iconRunGap.{cfg.sizeRole}.{if classes.touch == true then "touch" else "pointer"}`
		end))
		else `iconRunGap.{cfg.sizeRole}.pointer`

	-- `readOnly` is a refusal ON TOP of the contract's reading of `enabled`: a
	-- read-only picker still paints and still takes a focus stop, it just never
	-- changes
	local function isEnabled(): boolean
		return not readOnly and controlContract.enabledNow(cfg.enabled)
	end

	-- THE ONE MUTATION SITE: every input class routes here, so "what a level may
	-- be" is decided once instead of once per affordance.
	local function apply(next_: number): boolean
		if not isEnabled() then
			return false
		end
		local resolved = math.clamp(math.floor(next_ + 0.5), minValue, count)
		if resolved == value:get() then
			return false
		end
		value:set(resolved)
		if cfg.onChange ~= nil then
			cfg.onChange(resolved)
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

	-- ===== ONE MARK, THREE WAYS TO PAINT IT =================================
	-- Every branch below builds ONE leaf whose content is a memo over the shared
	-- value, so a level change is PAINT: exactly `count` prop writes, zero
	-- re-solves, no node created or destroyed. The tint is the second memo and it
	-- rides the same channel (`dirty = { "paint" }`, `channel = "binding"`) — so
	-- adding colour to this control cost nothing in the solver.
	local hasTint = cfg.tint.filled ~= nil or cfg.tint.empty ~= nil
	local marks = {}
	for i = 1, count do
		local index = i
		local function filledAt(use: any): boolean
			return use(value) >= index
		end
		-- nil is a legal value on a reactive binding and CLEARS the prop, which is
		-- what "omitting one half leaves it to the theme" has to mean: the empty
		-- marks of a picker that tinted only its filled half must reach paint
		-- carrying nothing, not carrying the other half's colour.
		local tint = if hasTint
			then scope:own(core:memo(function(use)
				return if filledAt(use) then cfg.tint.filled else cfg.tint.empty
			end))
			else nil
		local markId = `{cfg.names.mark}{index}`

		if cfg.segment == "bar" then
			-- THE BAR FILLS ITS CELL ON BOTH AXES. Width: the Grid's uniform column
			-- pitch is `innerWidth / columns`, so ten bars and three bars are the
			-- same declaration and the run reflows with its container for free.
			-- Height: the strip's own 44px floor IS the bar's height, which is why
			-- the reference screenshot's ten-segment picker reads as tall thin bars
			-- and its three-segment one as wide blocks — one declaration, both
			-- pictures.
			marks[i] = UI.Box({
				id = markId,
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				tint = tint,
			})
		elseif cfg.segment == "image" then
			local images = cfg.images :: { filled: string, empty: string }
			marks[i] = UI.Image({
				id = markId,
				image = scope:own(core:memo(function(use)
					return if filledAt(use) then images.filled else images.empty
				end)),
				-- `fit` and a SQUARE box off the icon ladder: a level's art must not
				-- change the run's arithmetic depending on the aspect ratio of an
				-- asset the control never sees
				scaleMode = "fit",
				width = { type = "fixed", px = markSize },
				height = { type = "fixed", px = markSize },
				tint = tint,
			})
		else
			local glyphs = cfg.glyphs :: { filled: string, empty: string }
			marks[i] = UI.Text({
				id = markId,
				text = scope:own(core:memo(function(use)
					return if filledAt(use) then glyphs.filled else glyphs.empty
				end)),
				-- THE GLYPH IS SIZED; THE BOX HUGS IT, AND THE HUG TRACKS THE SCALE
				-- (found live 2026-08-06 on the console ten-foot matrix row). This was
				-- `{ type = "minMax", max = markSize }`, capping the box at the icon
				-- METRIC — an unscaled number — while the glyph beside it is painted
				-- at `textSize * typographyScale`. At the ten-foot profile's 1.5x every
				-- one of the playlist's stars reported `textFits = false`: the box was
				-- 16px and the star drew at 24. `hug` is CONTENT WITH THE PARENT'S
				-- OFFER AS A CEILING (solver `resolveAxis`), so room to spare -> the
				-- mark is glyph-sized and the run groups; not enough room -> it shrinks
				-- to the share it was offered, and the cap can never fall below the
				-- glyph again.
				textSize = markSize,
				textAlign = "center",
				width = { type = "hug" },
				tint = tint,
				-- NOT a Button, and therefore not a `control` to any theme: a level is
				-- a mark, and the whole point of this control is that it wears one
				-- surface (none) rather than `count` of them.
			})
		end
	end

	-- A CONTENT MARK GROUPS; A BAR DIVIDES. A glyph and an image are content, so
	-- the run hugs them and centres in whatever column it is given (the 2026-07-27
	-- grouping ruling). A bar reports no content of its own — it IS a share — so a
	-- hug run would collapse to just the gaps, which is exactly what the rating's
	-- own history records happening to `fill` stars. One `if`, and it is the only
	-- place the three segments differ in layout.
	local runFills = cfg.segment == "bar"
	local run = UI.Grid({
		id = cfg.names.run,
		-- A GRID, NOT AN HSTACK, SO THE MARKS SHRINK TOGETHER (found live
		-- 2026-08-06 at preferredTextSize = Largest on a compact phone). An HStack
		-- of hug children that cannot all fit clamps in order and STARVES THE TAIL:
		-- the last mark was handed a zero-width box and simply vanished. `UI.Grid`
		-- with `columns = count` and `itemSizing = "uniform"` makes every mark the
		-- same width by construction, so a short offer shrinks all of them evenly
		-- instead of dropping the last ones.
		columns = count,
		itemSizing = "uniform",
		gap = markGap,
		width = if runFills then { type = "fill", weight = 1 } else { type = "hug" },
		height = if runFills then { type = "fill", weight = 1 } else nil,
		-- CENTRED IN WHATEVER COLUMN IT IS GIVEN (director, 2026-07-27). A hugging
		-- run no longer reaches both edges of a generous cell, so where the slack
		-- goes is a visible decision: a strip pinned to the leading edge of a wide
		-- column reads as misaligned with its own header. This works because the
		-- ROOT is a ZStack and `alignH` is honoured for zstack children — an HStack
		-- ignores it, so putting it there would have been accepted-and-ignored.
		alignH = if runFills then nil else "center",
		children = marks,
	})

	local root = UI.ZStack({
		id = id,
		-- the strip takes the box it is given: `fill` here is what lets the shares
		-- above be shares OF something. In a content-sized parent a `fill` measures
		-- as its own content, so a standalone picker still hugs its marks.
		width = { type = "fill", weight = 1 },
		-- THE 44px EFFECTIVE TARGET, DECLARED (new-control playbook §3: the floor
		-- is a contract you declare, not one the solver enforces). It is load-
		-- bearing for `bar`, whose marks have no content height at all — without it
		-- the whole strip solves to nothing a finger can hit — and it is the right
		-- answer for the content segments too, whose glyph is smaller than a
		-- fingertip. A theme METRIC, so a package with a bigger minimum target gets
		-- a bigger strip.
		height = if cfg.targetFloor then { type = "minMax", min = "targetSizes.minimum" } else nil,
		children = {
			run,
			-- THE STRIP IS THE CONTROL. One Grip over the marks: one focus stop, one
			-- effective target, one place pointer input lands. A read-only picker
			-- drops out of the focus ring entirely rather than offering a ring that
			-- does nothing.
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
					-- CANCEL, not commit (the hotSwitch decision above): put back what
					-- was there before the scrub started
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
		-- focus-gated Adjust (ADR-0013): the strip is the adjust target, so keyboard
		-- Comma/Period and gamepad L1/R1 reach the same arithmetic while focus sits
		-- on this control — and are UNBOUND otherwise. `rootNode` is THIS CONTROL's
		-- mounted root: handed the screen root, "every Grip below here" claimed the
		-- whole screen (found live 2026-08-02).
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
		-- the strip runs left to right, so Left/Right ARE the picker (roadmap
		-- Step 8); Up/Down keep navigating away from it. Returning false at the
		-- limit is what gives the arrow back to navigation (ruling 9, 2026-08-14).
		adjustAxis = "horizontal",
		handleAdjust = function(_path: string, direction: number): boolean
			return apply(value:get() + direction)
		end,
	})

	local api = {}
	api.blueprint = built

	-- HOT SWITCH (UI-PARADIGM-003), the same seam Slider publishes: the host tells
	-- the control its pointer class went away, and a live scrub reverts to the
	-- value the player started from. A half-finished drag must never commit.
	function api.onInteractionClassLost(class: string)
		if (class == "pointer" or class == "touch") and scrubFrom ~= nil then
			apply(scrubFrom)
			scrubFrom = nil
		end
	end

	-- the value IN ITS RANGE, so a ten-foot readout or an assistive layer never
	-- gets a bare number with no context (the B-VAL1 shape Slider/Stepper share).
	-- It is the whole accessible identity of a control made of bars: a strip of
	-- ten rectangles says nothing to a non-visual consumer, and `dump()` carries
	-- this string for exactly that reason.
	api.semanticText = scope:own(core:memo(function(use)
		return `{use(value)} of {count}`
	end))

	-- the authoring notes this build produced — a WARNING channel, never a
	-- refusal (see HIGH_COUNT). Cloned, so a caller cannot edit the control's own
	-- record of what it complained about.
	function api.diagnostics(): { string }
		return table.clone(cfg.diagnostics)
	end

	--[[ THE FACTS, WITHOUT THE SCHEMA — and the split is not bookkeeping. A dump
		schema string is a promise a SPECIFIC constructor makes to its own
		consumers (`facet-rating-dump/1` has been in the field since 2026-07-26),
		so a shared body must not be able to renumber one control's contract by
		editing the other's. Each public entry stamps its own onto these fields,
		which is also exactly what `check_registration` §10.2 asks for: a `dump`
		DEFINITION in the module whose registry row cites it. Returned beside the
		api rather than on it, so it is not a public member of either control. ]]
	local function facts()
		return {
			id = id,
			-- WHAT ONE LEVEL IS PAINTED AS. A bar- or image-only control is
			-- unreadable to every non-visual consumer without this pair: `segment`
			-- says what a bug report is looking at, and `semanticText` says what it
			-- MEANS.
			segment = cfg.segment,
			value = value:get(),
			count = count,
			min = minValue,
			readOnly = readOnly,
			enabled = isEnabled(),
			semanticText = api.semanticText:get(),
			diagnostics = table.clone(cfg.diagnostics),
			rootPath = rootPath,
		}
	end

	function api.dispose()
		scope:dispose()
	end

	return api, facts
end

function level_picker.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newLevelPicker", spec, LEVEL_PICKER_KEYS, "spec")
	local id = spec.id or "LevelPicker"
	local count = if spec.count ~= nil then spec.count else 5
	validate("newLevelPicker", id, spec.value, count)

	local segment = spec.segment or level_picker.DEFAULT_SEGMENT
	if not SEGMENTS[segment] then
		error(
			`Facet newLevelPicker('{id}'): unknown segment '{tostring(spec.segment)}' — use one of `
				.. `{SEGMENT_LIST} ("bar" is the default and needs no assets).`,
			0
		)
	end

	-- EACH PAIR DESCRIBES ONE SEGMENT, so declaring the other one is an authoring
	-- error rather than a silent no-op (constitution §4, and the shape
	-- `newProgressView`'s `min`-on-an-indeterminate-view refusal already takes):
	-- `glyphs = { … }` beside `segment = "bar"` is a caller who believes they are
	-- looking at glyphs.
	if spec.glyphs ~= nil and segment ~= "glyph" then
		error(
			`Facet newLevelPicker('{id}'): \`glyphs\` describes a glyph segment, and this picker is a `
				.. `"{segment}" — it would be accepted and ignored. Drop it, or use \`segment = "glyph"\`.`,
			0
		)
	end
	if spec.images ~= nil and segment ~= "image" then
		error(
			`Facet newLevelPicker('{id}'): \`images\` describes an image segment, and this picker is a `
				.. `"{segment}" — it would be accepted and ignored. Drop it, or use \`segment = "image"\`.`,
			0
		)
	end
	if segment == "image" and spec.images == nil then
		error(
			`Facet newLevelPicker('{id}'): \`segment = "image"\` needs \`images = \{ filled, empty }\` — this `
				.. "control never names an asset of its own, so there is no default to fall back to. Use "
				.. '`segment = "bar"` (no assets at all) or `segment = "glyph"`.',
			0
		)
	end

	local diagnostics: { string } = {}
	diagnoseCount("newLevelPicker", id, count, diagnostics)

	local api, facts = level_picker.compose(Facet, core, {
		constructor = "newLevelPicker",
		names = { run = "Levels", mark = "Level" },
		id = id,
		value = spec.value,
		count = count,
		minValue = if spec.allowZero == false then 1 else 0,
		segment = segment,
		sizeRole = sizeRole("newLevelPicker", id, "segmentSize", spec.segmentSize),
		glyphs = if segment == "glyph"
			then spec.glyphs or { filled = level_picker.GLYPH_FILLED, empty = level_picker.GLYPH_EMPTY }
			else nil,
		images = spec.images,
		-- the BAR's two halves have a default because a bar has no other way to
		-- say "filled"; a glyph and an image do, so theirs is nothing at all and a
		-- caller's `tint` is purely additive there (a star that suddenly carried a
		-- default tint would repaint every rating this framework ships).
		tint = if segment == "bar"
			then {
				filled = if spec.tint ~= nil and spec.tint.filled ~= nil
					then spec.tint.filled
					else DEFAULT_BAR_TINT.filled,
				empty = if spec.tint ~= nil and spec.tint.empty ~= nil then spec.tint.empty else DEFAULT_BAR_TINT.empty,
			}
			else {
				filled = if spec.tint ~= nil then spec.tint.filled else nil,
				empty = if spec.tint ~= nil then spec.tint.empty else nil,
			},
		targetFloor = true,
		readOnly = spec.readOnly == true,
		enabled = spec.enabled,
		env = spec.env,
		onChange = spec.onChange,
		diagnostics = diagnostics,
	})

	-- THIS CONTROL'S OWN DUMP, and its first version. `/1` rather than `/2` is
	-- not a judgement call here: nothing published `facet-level-picker-dump`
	-- before this round, so there is no consumer for a `/2` to be compatible
	-- with. (`newRating`'s dump is the one with history, and it stays `/1` for
	-- the opposite reason — every key it carried still carries the same value,
	-- and `segment` is purely additive.)
	function api.dump()
		local out = facts()
		out.schema = "facet-level-picker-dump/1"
		return out
	end

	return api
end

-- the preset's seam, so `src/controls/rating.luau` stays the file a reader opens
-- for `newRating` and this one stays the file the behaviour lives in
level_picker.validate = validate
level_picker.sizeRole = sizeRole
level_picker.diagnoseCount = diagnoseCount

return level_picker
