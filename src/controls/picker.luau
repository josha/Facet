--!strict
-- Picker: single-selection from a small option set (docs/plans/parity-next.md
-- investment 7; acceptance row B-DSP2). Two presentations over ONE selection model:
--
--   segmented — options side by side, always visible. Good for 2–4 short options.
--   inline    — options stacked as rows. Good for longer labels or more options.
--
-- The presentation is ADAPTIVE, not a platform branch: `presentation = "automatic"`
-- (the default) chooses from the option count and the available space class the
-- caller passes in, exactly as `Facet.adaptive` computes it. A device name never
-- appears. For a popup presentation use `newPopupButton`, which owns the transient
-- surface machinery.
--
-- THREE AXES: every option is a focusable Button, so reachability and the 44px
-- floor come from the primitive; the selected option carries `selected`, which is
-- a style TAG, not a bespoke fill. hotSwitch = false (selection is atomic).
--
-- OWNERSHIP: `selected` is the CALLER's Signal.
--
-- ===== THE SLIDING INDICATOR (navigation-and-menus D4, adopted in D6) ======
--
-- `indicator = "automatic" (default) | "none" | "underline" | "pill"` is the
-- PUBLIC authoring surface for the D4 seam — the mechanism is internal
-- (`src/controls/selection_indicator.luau`) and nobody instantiates it directly.
-- When it is on, the selection chip or bar SLIDES from the previously selected
-- option's solved rect to the new one instead of the fill cross-fading.
--
-- `"automatic"` RESOLVES TO THE PILL unless the caller declared the stacked row
-- list. D4 shipped the property defaulting to `"none"` so that nothing already
-- on screen moved, which was right for a stage whose job was the mechanism; it
-- is wrong to leave, because a mechanism nobody consumes by default is an
-- unproven mechanism, and every reference screenshot of a segmented control
-- (r3, f1's top pill, f1's left rail) draws a chip. So:
--
--     presentation "inline" DECLARED  ->  "none"   (the row list never wore one)
--     anything else                   ->  "pill"
--
-- The second rule deliberately covers `presentation = "automatic"`, which is
-- what most callers write: a default that only reached a DECLARED `segmented`
-- would change almost nothing. An adaptive picker that flips to its stacked form
-- therefore carries its chip down with it — ONE selection paint re-solved, which
-- is what the A-AL2 rule (a presentation flip is a re-solve, not a rebuild)
-- already promises for everything else about this control. `indicator = "none"`
-- is the documented escape hatch back to the static style tag.
--
-- Two consequences, both deliberate and both stated here because they change
-- what the control paints:
--
--   * THE INDICATOR IS THEN THE SELECTION PAINT. The option Buttons stop
--     carrying the `selected` style tag and are declared `surface = "plain"`,
--     because a tag AND a chip is the same statement twice — and worse, an
--     opaque Button would paint OVER the chip that is meant to sit behind its
--     label. Selection stays fully reported by `dump()`.
--   * `axis` becomes meaningful. `axis = "y"` with the SEGMENTED presentation is
--     f1's vertical rail: a real vertical pill, which is a different shape from
--     the `inline` row list and does not overload it — see below.
--
-- ===== THE VERTICAL PILL IS NOT THE INLINE ROW LIST (D6) ==================
--
-- Both stack their options along y, so both report `axis = "y"`, and that is
-- exactly why they are computed as two separate facts here (`verticalPill` and
-- `axis`) rather than one. What tells them apart is the CONTAINER:
--
--     vertical pill   a content-sized RAIL with a 44px floor: as wide as its
--                     widest segment and no wider, so it sits at the edge of a
--                     screen the way f1's left rail does. Its segments are
--                     cross-axis `fill`, so they all share that one width.
--     inline row list a FULL-WIDTH column: each row spans the offer, which is
--                     what makes it a list of rows rather than a control.
--
-- The floor matters because an icon-only rail has nothing wide in it: three
-- glyphs solve to 36px, which is under the tap target, and the height floor on
-- the segments cannot see it. `dump().verticalPill` reports the distinction so a
-- bug report about "the picker is full width" has a field to name.
--
-- ===== ICONS ON AN OPTION (D6) ============================================
--
-- `Option.icon` is a SEMANTIC ICON NAME, never an asset id — the same currency
-- `row_actions.ActionSpec.icon` spends, so a package that ships art for that
-- name paints it and one that does not draws the framework's ASCII-safe glyph.
-- It rides `compactLabel` on the option Button, because `Button.icon` (the
-- top-level prop) is circle-only and a segment is a rectangle.
--
-- WHICH REPRESENTATION IS THE DEFAULT is the device-round director ruling of
-- 2026-08-12, and this control follows it rather than writing a second one:
--
--     iconOnly = false (default)  the segment KEEPS ITS WORD and wears the glyph
--                                 only when the word does not fit — the MENU-ROW
--                                 reading (`row_actions.luau:1774`: "a menu row
--                                 is a list of names; it is where the words
--                                 live"). Authoring both is authoring a ladder.
--     iconOnly = true             `prefer = true`: the glyph is what every
--                                 segment wears at every width — the TRAY
--                                 reading (`row_actions_trays.luau:346`), and
--                                 what f1's top pill and left rail both draw.
--
-- It is a GROUP decision, not a per-option one, for the same reason the tray
-- ruling gives: a per-segment verdict makes one plate wear a glyph while its
-- neighbour wears a word. The menu guidance says the same — "provide
-- icons for all menu items in a group, or none of them — so a half-iconned
-- group is an authoring ERROR here, not a look somebody has to notice.
--
-- `label` stays REQUIRED and non-empty whatever is drawn: it is the semantic
-- name, it is what `dump().semanticText` announces, and an icon with no name is
-- unreadable to every non-visual consumer.
--
-- ===== D5 COMPOSES THIS STRIP =============================================
--
-- "A segmented picker used as a tab bar IS a TabView" — so D5's TabView builds
-- its strip out of THIS control rather than reimplementing the row (director
-- call, `artifacts/navigation-and-menus/additive-vs-net-new.md` §6). Keep the
-- option row reusable: no tab-specific knowledge belongs in here, and anything
-- a strip needs (icons, the axis, the indicator) is a property.
--
-- D5 took that literally. It needed four things and every one of them landed
-- HERE, as a property or a widening, rather than as a second option row:
--
--   sizing = "fill" | "hug"   `fill` (the default, and what every pre-D5 caller
--                             gets) divides the offer among the segments, which
--                             is why a `fill` strip CAN NEVER OVERFLOW: five
--                             tabs at 320px are 64px each. An overflowing tab
--                             strip — f1's `Avatars / Body / Clothing /
--                             Accessories / Backg…` — is a `hug` one, whose
--                             segments take their natural widths and whose band
--                             takes theirs, so it can be wider than the offer and
--                             a scroll host has something to scroll.
--   axis   as a Readable      a tab bar's HOME moves under a live rotation
--                             (`adaptive.navPlacement`: sidebar -> a vertical
--                             rail, bottom bar -> a horizontal band), and the
--                             A-AL2 rule says an arrangement change is a
--                             RE-SOLVE, not a rebuild. A build-time axis would
--                             have forced two strips under two `When`s, which
--                             is exactly the hand-assembly D5 exists to delete.
--                             `sizing` is a Readable for the same reason.
--   Option.badge              the count seal. Not tab-specific at all: a
--                             segmented control over a message list wants one
--                             too, and `surface = "badge"` is a shipped Text
--                             token, so this adds no primitive.
--   Option.label as Readable  the reference shells carry a SECOND localized
--                             string for the thumb zone ("nav.menu.short") and
--                             flip between them live, which a build-time string
--                             cannot follow. `compactLabel` is deliberately not
--                             reactive (a compact form is what a control HAS),
--                             so the binding has to be the label itself.
--
-- A BADGED OPTION GAINS ONE WRAPPER NODE, and only a badged one. The badge is a
-- decoration ON the segment, so it cannot be a Button CHILD: a Button with
-- children draws no text at all (`renderer.luau:913` — "a content button's label
-- is SEMANTICS, not paint"), which would take the word away from every segment
-- that carries a count and throw out the compactLabel degrade ladder with it. It
-- is therefore an overlay SIBLING inside a per-segment `ZStack` — the shape
-- `p4_foyer`'s `badgeBubble` already ships over its friend tiles — and the
-- Button keeps its own id, so activation (which dispatches on the LEAF id) and
-- the indicator (which resolves the SEGMENT by id) are both untouched. An
-- unbadged picker mounts no wrapper and no badge node, so every path that
-- shipped before D5 is byte-identical.

local chrome_slots = require("../tokens/chrome_slots")
local controlContract = require("../class_contract")
local contribution = require("../input/contribution")
local selectionIndicator = require("./selection_indicator")
local specGuard = require("../spec_guard")
local surfaceEnv = require("../env/surface_env")
local themeSnapshot = require("../themes/snapshot")

local picker = {}

-- `icon` is a SEMANTIC NAME ("close", "chevron.trailing", a namespaced
-- "ns:name"), never an asset id. `label` is required whatever is drawn, and may
-- be a string or a Readable of one (D5: the reference shells flip between a full
-- and a terse localized name live). `badge` is the count seal — a string, a
-- number, or a Readable of either; an empty one hides the plate rather than
-- painting an empty bubble.
export type Option = { value: any, label: any, icon: string?, badge: any? }

export type Spec = {
	id: string?,
	label: string?,
	options: { Option },
	selected: any, -- owner-held Signal
	presentation: string?, -- "automatic" (default) | "segmented" | "inline"
	-- "automatic" (default) | "none" | "underline" | "pill" — the D4 sliding
	-- selection indicator. "automatic" is the PILL unless `presentation =
	-- "inline"` was declared, in which case it is "none" (see the header).
	indicator: string?,
	-- "x" (default) | "y" — the SEGMENTED presentation's axis, or a Readable of
	-- either. "y" is a vertical PILL (f1's left rail), which is a different shape
	-- from the `inline` row list and deliberately does not overload it. Inert
	-- under `inline`, which is a column by definition. REACTIVE because a tab
	-- bar's home moves under a live rotation and an arrangement change is a
	-- re-solve, not a rebuild (A-AL2).
	axis: any?,
	-- "fill" (default) | "hug", or a Readable of either. `fill` divides the offer
	-- among the segments — the shape every pre-D5 caller has; `hug` gives the band
	-- and every segment its natural width, which is what lets a strip be WIDER
	-- than its offer and therefore scroll (f1's overflowing tab strip). Inert on
	-- the vertical rail, which is content-sized by definition.
	sizing: any?,
	-- true makes the option ICON what every segment wears at every width, with
	-- `label` staying the semantic name (f1's icon-only pill and rail). Default
	-- false: the segment keeps its word and degrades to the glyph. A GROUP
	-- decision — see the header on why it cannot be per-option.
	iconOnly: boolean?,
	-- the TYPE ROLE every segment wears (a `TypeRole` name or a number, or a
	-- Readable of either), passed straight to each segment's Button. Nil is the
	-- Button's own default, which is what every caller before §6 had. REACTIVE for
	-- the same reason `axis` and `sizing` are: a strip's home moves under a live
	-- rotation and a tab bar in the thumb zone is caption-sized while the same
	-- strip on a rail is not.
	textSize: any?,
	sizeClass: any?, -- string | Readable<string> from Facet.adaptive.conditions
	env: any?, -- optional environment, so the indicator's metrics follow a live theme
	enabled: any?,
	onChange: ((value: any) -> ())?,
}

local PRESENTATIONS: { [string]: boolean } = { automatic = true, segmented = true, inline = true }
local INDICATORS: { [string]: boolean } = { automatic = true, none = true, underline = true, pill = true }
local AXES: { [string]: boolean } = { x = true, y = true }
local SIZINGS: { [string]: boolean } = { fill = true, hug = true }

-- THE THREE CONTAINER SHAPES, hoisted so the memos below return a STABLE table
-- rather than a fresh one per evaluation (a dimension compared by identity would
-- otherwise re-solve on every read).
--
--   band  the horizontal segmented control and the inline row list: both span
--         the offer, and the segments divide it.
--   rail  the VERTICAL pill: as wide as its widest segment and no wider (f1's
--         left rail), floored at the tap target because an icon-only rail's
--         natural width is a glyph — measured at 36px, which is under it.
--   hug   `sizing = "hug"` (D5): the band takes its NATURAL width, uncapped, so
--         it can be wider than the offer and a scroll host has something to
--         scroll. `content`, never `hug`-the-solver-word — and the REASON changed
--         on 2026-08-22 while the choice did not. It used to be "a capped width
--         can never report that it did not fit (the reference shells' own
--         ViewThatFits finding)"; the fit declaration closed that at the seam, so a `hug`
--         candidate reports its ideal size like any other. What stands is the
--         plain one: this band must be able to be WIDER THAN ITS OFFER so the
--         scroll host has something to scroll, and `hug` caps at the offer by
--         definition. `content` is the word for "uncapped natural width".
local BAND_WIDTH = table.freeze({ type = "fill", weight = 1 })
local RAIL_WIDTH = table.freeze({ type = "minMax", min = "targetSizes.minimum" })
local NATURAL_WIDTH = table.freeze({ type = "content" })
-- ...and the two SEGMENT shapes. `fill` is what makes every segment the same
-- size — it divides the band and stretches each segment to the rail's resolved
-- width — while a hugging strip's segments take their own words' widths, which
-- is what makes "For you" wider than "Charts" and what the D4 indicator was
-- built to travel between (two rects, never two indices).
local SEGMENT_FILL = table.freeze({ type = "fill", weight = 1 })
local SEGMENT_NATURAL = table.freeze({ type = "content" })
local SEGMENT_HEIGHT = table.freeze({ type = "minMax", min = "targetSizes.minimum" })
local OVERLAY_FILL = table.freeze({ type = "fill", weight = 1 })
-- the count seal's own box. Both numbers are theme SPACING steps, so a package
-- published before this existed answers them and a theme that retunes its
-- spacing retunes the badge with it (the `selection_indicator` precedent).
local BADGE_BOX = table.freeze({ type = "minMax", min = "l" })
local BADGE_PAD = table.freeze({ left = "xs", right = "xs" })

-- the adaptive rule, pure and exported so a caller can predict it
function picker.resolvePresentation(optionCount: number, sizeClass: string?, longestLabel: number): string
	-- stack when the options cannot sit side by side legibly: too many of them, or
	-- long labels in a compact space. This is a SPACE decision, not a device one.
	if optionCount > 4 then
		return "inline"
	end
	if sizeClass == "compact" and (optionCount > 3 or longestLabel > 10) then
		return "inline"
	end
	return "segmented"
end

-- CLOSED SPEC (constitution §4). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local PICKER_KEYS = specGuard.keySet({
	"axis",
	"enabled",
	"env",
	"id",
	"iconOnly",
	"indicator",
	"label",
	"onChange",
	"options",
	"presentation",
	"selected",
	"sizeClass",
	"sizing",
	"textSize",
})

-- read a Readable-or-plain value, subscribing when a `use` is in hand. BOTH
-- reactive kinds, exactly as `selection_indicator.readValue` does and for the
-- same reason: `axis`/`sizing` arrive as a Signal from a test and as a MEMO from
-- a TabView whose placement is derived, and reading only one kind hands the
-- caller back the node itself.
local function readValue(source: any, use: any?): any
	if type(source) == "table" and ((source :: any).kind == "signal" or (source :: any).kind == "memo") then
		return if use ~= nil then use(source) else (source :: any):get()
	end
	return source
end

function picker.build(Facet: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newPicker", spec, PICKER_KEYS, "spec")
	local UI = Facet.UI
	local id = spec.id or "Picker"
	local scope = core:scope("picker-" .. tostring(id))
	if type(spec.options) ~= "table" or #spec.options == 0 then
		error(`Facet newPicker('{id}'): \`options\` must be a non-empty array of value/label pairs`, 0)
	end
	local selected = spec.selected
	if type(selected) ~= "table" or (selected :: any).kind ~= "signal" then
		error(`Facet newPicker('{id}'): \`selected\` must be a SETTABLE Signal the caller owns`, 0)
	end
	local requested = spec.presentation or "automatic"
	if not PRESENTATIONS[requested] then
		error(`Facet newPicker('{id}'): unknown presentation '{requested}'. One of automatic | segmented | inline.`, 0)
	end
	local indicatorRequest = spec.indicator or "automatic"
	if not INDICATORS[indicatorRequest] then
		error(
			`Facet newPicker('{id}'): unknown indicator '{tostring(indicatorRequest)}'. `
				.. "One of automatic | none | underline | pill. "
				.. "The sliding indicator is a PROPERTY of this control, not a construct you build yourself.",
			0
		)
	end
	-- THE D6 DEFAULT (see the header). "automatic" is the pill everywhere except
	-- a DECLARED row list, which never wore one. Resolved once, at build time:
	-- the skin is what the decoration IS, not a state it passes through, and the
	-- seam takes it as a build-time string for exactly that reason.
	local indicator = if indicatorRequest ~= "automatic"
		then indicatorRequest
		elseif requested == "inline" then "none"
		else "pill"
	-- `axis` and `sizing` may each be a plain string or a Readable (see the Spec
	-- comments). The CURRENT value of a Readable is validated here too, so a typo
	-- is still an authoring error rather than a wrong edge — but a later unknown
	-- value degrades to the default rather than throwing from inside a memo,
	-- which is `selection_indicator.axisNow`'s own tolerance for a reactive enum.
	local axisSource = if spec.axis == nil then "x" else spec.axis
	local function axisNow(use: any?): string
		local value = readValue(axisSource, use)
		return if AXES[value] then value else "x"
	end
	if not AXES[readValue(axisSource)] then
		error(
			`Facet newPicker('{id}'): unknown axis '{tostring(readValue(axisSource))}'. One of x | y. `
				.. '`axis = "y"` is the VERTICAL segmented pill; the stacked row list is `presentation = "inline"`.',
			0
		)
	end
	local sizingSource = if spec.sizing == nil then "fill" else spec.sizing
	local function sizingNow(use: any?): string
		local value = readValue(sizingSource, use)
		return if SIZINGS[value] then value else "fill"
	end
	if not SIZINGS[readValue(sizingSource)] then
		error(
			`Facet newPicker('{id}'): unknown sizing '{tostring(readValue(sizingSource))}'. One of fill | hug. `
				.. "`fill` divides the offer among the segments (and therefore can never overflow); `hug` gives "
				.. "the band and every segment its natural width, which is what an overflowing tab strip is.",
			0
		)
	end

	-- ===== the option lint (D6) ===========================================
	-- Three authoring rules, all enforced here rather than left to be noticed on
	-- a screen: a segment always has a NAME, a group is all-iconned or none, and
	-- `iconOnly` needs something to draw.
	local longest = 0
	local iconCount = 0
	local badgeCount = 0
	-- LABEL SNAPSHOT. A bound label is validated and MEASURED at its current
	-- value: `resolvePresentation` takes a longest-label number, which is a
	-- build-time fact by contract (it decides the presentation, and a presentation
	-- that re-derived itself from every keystroke of a locale flip would be a
	-- second adaptive authority beside `sizeClass`). The DRAWN label stays fully
	-- bound; only this measurement is a snapshot, and that is said out loud here
	-- rather than discovered.
	local function labelNow(option: any): any
		return readValue(option.label)
	end
	for index, option in spec.options do
		if type(option) ~= "table" then
			error(`Facet newPicker('{id}'): option {index} must be a table of value / label / optional icon`, 0)
		end
		local labelText = labelNow(option)
		if type(labelText) ~= "string" or labelText == "" then
			error(
				`Facet newPicker('{id}'): option {index} needs a non-empty \`label\`. It is the SEMANTIC name — `
					.. "what `dump().semanticText` announces and what an icon-only segment has instead of "
					.. "readable text. An icon with no name is unreadable to every non-visual consumer.",
				0
			)
		end
		if option.badge ~= nil then
			local badgeText = readValue(option.badge)
			if type(badgeText) ~= "string" and type(badgeText) ~= "number" then
				error(
					`Facet newPicker('{id}'): option {index}'s \`badge\` must be a string or a number (or a `
						.. "Readable of one) — the COUNT the seal shows. An empty one hides the plate rather "
						.. "than painting an empty bubble.",
					0
				)
			end
			badgeCount += 1
		end
		if option.icon ~= nil then
			if type(option.icon) ~= "string" or option.icon == "" then
				error(
					`Facet newPicker('{id}'): option {index}'s \`icon\` must be a semantic icon NAME `
						.. '("close", "chevron.trailing", "ns:name"), never an asset id.',
					0
				)
			end
			iconCount += 1
		end
		longest = math.max(longest, #labelText)
	end
	if iconCount > 0 and iconCount < #spec.options then
		error(
			`Facet newPicker('{id}'): {iconCount} of {#spec.options} options carry an \`icon\`. Provide icons for `
				.. "all options in a group, or none of them — a half-iconned group reads as a "
				.. "mistake at every width except the one it was authored at.",
			0
		)
	end
	if spec.iconOnly ~= nil and type(spec.iconOnly) ~= "boolean" then
		error(`Facet newPicker('{id}'): \`iconOnly\` must be a boolean`, 0)
	end
	local iconOnly = spec.iconOnly == true
	if iconOnly and iconCount == 0 then
		error(
			`Facet newPicker('{id}'): \`iconOnly\` was asked for but no option carries an \`icon\`, so there `
				.. "would be nothing to draw. Give every option an icon, or drop `iconOnly`.",
			0
		)
	end

	--[[ THE SIZE CLASS ARRIVES BY ITSELF (2026-08-18).

		`sizeClass` nil used to mean `readSizeClass` returned nil, which made the
		COMPACT branch of `resolvePresentation` unreachable: an automatic picker
		took the large-screen answer, on every device, forever, and said nothing.
		Measured across `examples/`: not one of seventeen call sites used the
		adaptive default and ten disabled it outright.

		Now an automatic presentation with no authored class asks the environment —
		the one the author passed, or the one this control's own core published
		(`src/env/surface_env.luau`) — and REFUSES to construct when there is
		none, in `tab_view`'s shape and for its reason: adaptation must not be able
		to silently not happen. A control that must NOT adapt still says so the way
		it always did, by declaring `presentation`. ]]
	local sizeClassSource: any = spec.sizeClass
	local sizeClassFrom = if spec.sizeClass ~= nil then "spec" else "none"
	if requested == "automatic" and sizeClassSource == nil then
		local env, source =
			surfaceEnv.resolve("newPicker", id, core, spec.env, "an automatic presentation adapts to the size class")
		sizeClassSource = env:get("sizeClass")
		sizeClassFrom = source
	end

	local function readSizeClass(use: any?): string?
		local sc = sizeClassSource
		if sc == nil then
			return nil
		end
		if type(sc) == "table" then
			return if use ~= nil then use(sc) else (sc :: any):get()
		end
		return sc :: string
	end

	local presentation = scope:own(core:memo(function(use)
		if requested ~= "automatic" then
			return requested
		end
		return picker.resolvePresentation(#spec.options, readSizeClass(use), longest)
	end))

	-- ONE class with a reactive axis, so a presentation flip is a re-solve and the
	-- option buttons keep their identity, focus and state (the A-AL2 rule).
	-- `axis = "y"` on the SEGMENTED presentation is the vertical PILL; `inline` is
	-- a column by definition and ignores it.
	local axis = scope:own(core:memo(function(use)
		return if use(presentation) == "segmented" then axisNow(use) else "y"
	end))

	-- ...and the fact `axis` alone CANNOT express, because the vertical pill and
	-- the inline row list both answer "y". Two names for two facts is the whole
	-- guard against confusing them; it also drives the container shape below and
	-- is reported by `dump()`.
	local verticalPill = scope:own(core:memo(function(use)
		return use(presentation) == "segmented" and axisNow(use) == "y"
	end))

	-- the RAIL hugs (floored at the tap target); a HUGGING band takes its natural
	-- width; the filling band and the row list take the offer. Reactive because
	-- all three inputs are: an adaptive picker that flips out of segmented must
	-- give the offer back, and a tab bar that moves from a bottom band to a
	-- centered cluster must stop filling — a build-time width would leave a 44px
	-- column standing where a full-width row list belongs.
	local groupWidth = scope:own(core:memo(function(use)
		if use(verticalPill) then
			return RAIL_WIDTH
		end
		return if sizingNow(use) == "hug" then NATURAL_WIDTH else BAND_WIDTH
	end))

	-- the SEGMENT's own width, and it is a different question from the group's.
	-- On the rail this is the CROSS axis, where `fill` is what makes every segment
	-- share the rail's one resolved width; in a filling band it is the main axis,
	-- where `fill` divides the offer equally. Only a HUGGING band lets a segment
	-- take its own word's width — which is what makes "For you" wider than
	-- "Charts", and what a strip has to do before it can overflow at all.
	local segmentWidth = scope:own(core:memo(function(use)
		if use(verticalPill) then
			return SEGMENT_FILL
		end
		return if sizingNow(use) == "hug" then SEGMENT_NATURAL else SEGMENT_FILL
	end))

	-- the contract's one reading of `enabled` (a one-shot read: never subscribes)
	local function isEnabled(): boolean
		return controlContract.enabledNow(spec.enabled)
	end

	local function choose(value: any): boolean
		if not isEnabled() or selected:get() == value then
			return false
		end
		core:transaction(function()
			selected:set(value)
			if spec.onChange ~= nil then
				spec.onChange(value)
			end
		end)
		return true
	end

	-- one row per option. Without an indicator, `selected` is a BINDING prop that
	-- rides a style tag; WITH one, the indicator is the selection paint and the
	-- buttons go plain so nothing paints over the chip behind them (see header).
	local slides = indicator ~= "none"

	--[[ BADGE_CLEAR_SLOT + badgeCornerInset (task THEME2, director item 2: "the
		badge has no padding and overlaps the edge of the control", i2.png — a
		count seal straddling a Pixel Quest segment's own plank border).

		The count seal used to anchor flush to the segment cell's raw corner —
		zero inset, on every package. That is invisible on a flat theme (nothing
		is painted under the corner to overlap) and wrong on any package that
		carves a border into whatever surface actually paints behind this segment,
		which is EXACTLY `selection_indicator.luau`'s own `barSurfaceSlot` finding
		(director item 8, "tab font has no padding, overlaps
		edge") one seam over: a decoration that ignores the themed chrome inset
		the themed-chrome round made available collides with it.

		WHICH SURFACE PAINTS UNDER THE BADGE is exactly what decides `surface`
		on the option Button four lines below, so the same branch is read here:
		`indicator = "none"` -> the option's OWN surface (nil -> classifies to
		`control` by CLASS alone, the Button/Toggle fallback rule); any sliding
		indicator's bar wears `surface = "accent"` when it paints at all (`pill`)
		or nothing chrome-carrying at all (`underline`, a tint-only rule) — and
		`chrome_slots.classify` resolves BOTH `control` and `accent` to the same
		`control` decoration slot, so one lookup covers every indicator except
		`underline`, whose (still-`plain`) option surface classifies to nil.

		Costs nothing unless a badge exists (`badgeCount` is counted above) and
		moves no pixel on a flat package: `chromeInsets.control` is all-zero
		there (the themed-chrome round's own "flat packages are byte-identical" guarantee), so
		`carved` stays 0 and `padding` stays the same `{}` it always solved to. ]]
	local badgeClearSlot: string? = if indicator == "underline"
		then nil
		else chrome_slots.classify({ class = "Button", surface = if indicator == "none" then nil else "accent" })
	local badgeCornerInset: any = nil
	if badgeCount > 0 then
		local metricsSig = scope:own(core:memo(function(use)
			if spec.env == nil then
				return themeSnapshot.neutral()
			end
			local raw = use((spec.env :: any):get("themeMetrics"))
			return if type(raw) == "table" and type(raw.controls) == "table" then raw else themeSnapshot.neutral()
		end))
		badgeCornerInset = scope:own(core:memo(function(use)
			-- PER AXIS (review finding T1): a corner offset pads two independent
			-- sides, and `carvedBorder`'s shared four-sided max over-clears the
			-- short axis of any package whose `control` chrome is not itself
			-- symmetric (fantasy_ornate: top=10, right=14). `carvedSide` reads
			-- each axis on its own.
			local snap = use(metricsSig)
			local top = if badgeClearSlot ~= nil then chrome_slots.carvedSide(snap, badgeClearSlot, "top") else 0
			local right = if badgeClearSlot ~= nil then chrome_slots.carvedSide(snap, badgeClearSlot, "right") else 0
			return { top = top, right = right }
		end))
	end

	local rows: { any } = {}
	local byId: { [string]: any } = {}
	local segments: { any } = {}
	for i, option in spec.options do
		local optionId = "Opt" .. i
		byId[optionId] = option.value
		table.insert(segments, { value = option.value, id = optionId })
		local badged = option.badge ~= nil
		local button = UI.Button({
			id = optionId,
			-- ALWAYS the semantic name, whatever gets drawn (the row_actions
			-- ruling): `dump().semanticText` reads it, and the renderer's own
			-- icon branch keeps it as the announced name when the glyph wins.
			label = option.label,
			-- `prefer = true` INVERTS which representation is the default —
			-- the tray reading; without it the glyph is only the degrade, the
			-- menu-row reading. See the header for why this is a group call.
			compactLabel = if option.icon == nil
				then nil
				elseif iconOnly then { icon = option.icon, prefer = true }
				else { icon = option.icon },
			enabled = spec.enabled,
			textSize = spec.textSize,
			surface = if slides then "plain" else nil,
			selected = if slides
				then nil
				else scope:own(core:memo(function(use)
					return use(selected) == option.value
				end)),
			-- inside a badge wrapper the Button FILLS the cell, so the cell's own
			-- width (the reactive one) is the single place the segment's size is
			-- decided and the two can never disagree
			width = if badged then SEGMENT_FILL else segmentWidth,
			height = if badged then OVERLAY_FILL else SEGMENT_HEIGHT,
		})
		if not badged then
			table.insert(rows, button)
		else
			-- THE COUNT SEAL. A DECORATION, never a second activation site: a Text
			-- and a ZStack are neither focusable (focus_map.FOCUSABLE is Button /
			-- Toggle / TextField) nor interactive, so the engine still delivers the
			-- press to the Button underneath — the `p4_foyer` badgeBubble shape,
			-- and the reason it is a sibling rather than a Button child.
			local badgeText = scope:own(core:memo(function(use)
				local raw = readValue(option.badge, use)
				return if raw == nil then "" else tostring(raw)
			end))
			local badgeEmpty = scope:own(core:memo(function(use)
				return use(badgeText) == ""
			end))
			table.insert(
				rows,
				UI.ZStack({
					id = optionId .. "Cell",
					width = segmentWidth,
					height = SEGMENT_HEIGHT,
					children = {
						button,
						UI.ZStack({
							id = "Badge",
							alignH = "end",
							alignV = "start",
							width = OVERLAY_FILL,
							height = OVERLAY_FILL,
							-- clears the segment's own themed chrome border (see
							-- `badgeCornerInset` above); `{top=0,right=0}` on every flat
							-- package, so shipped geometry there is unchanged
							padding = badgeCornerInset,
							children = {
								UI.Text({
									id = "Count",
									surface = "badge",
									text = badgeText,
									-- an EMPTY count hides the plate rather than
									-- painting an empty bubble; `hidden` is a bound
									-- prop, so a count that arrives later simply
									-- appears without a structural change
									hidden = badgeEmpty,
									textSize = "caption",
									textAlign = "center",
									lineLimit = 1,
									width = BADGE_BOX,
									height = BADGE_BOX,
									padding = BADGE_PAD,
									corners = UI.cornersData("pill"),
								}),
							},
						}),
					},
				})
			)
		end
	end

	local group = UI.AdaptiveStack({
		id = "Options",
		axis = axis,
		gap = "xs",
		width = groupWidth,
		children = rows,
	})

	-- the D4 seam. It WRAPS the option stack, so the indicator layer and the
	-- options share one parent and the offsets it spends are in that parent's own
	-- space (see selection_indicator.luau on rectOf vs screenRectOf).
	local indicatorApi: any = nil
	if slides then
		indicatorApi = selectionIndicator.build(Facet, core, {
			id = "Indicator",
			content = group,
			segments = segments,
			selected = selected,
			skin = indicator,
			axis = axis, -- the LIVE axis: a presentation flip must move the edge with it
			env = spec.env,
			-- the wrapper inherits the option stack's own dimension, or the `fill`
			-- options inside it have nothing to fill and solve to ZERO width (the
			-- D4 defect the game rider found). The SAME memo rather than a copy of
			-- today's answer, so a rail and a band cannot disagree. Measured
			-- honestly: on the RAIL path this declaration is currently not
			-- observable — the root above and the option stack below both pin that
			-- width, so replacing it with the band's changes no solved rect. It is
			-- kept because it is the true statement, not because a test caught it.
			width = groupWidth,
		})
		scope:own(indicatorApi) -- the seam's whole lifetime is this control's
		group = indicatorApi.blueprint
	end

	-- ...and so does the control's own root, or a vertical rail would be a 44px
	-- pill floating at the leading edge of a full-width invisible column, and a
	-- caller placing it beside content in an HStack would lose the whole row to it
	local root = if spec.label ~= nil
		then UI.VStack({
			id = id,
			gap = "xs",
			width = groupWidth,
			children = { UI.Text({ id = "Label", text = spec.label, textSize = "label" }), group },
		})
		else UI.VStack({ id = id, width = groupWidth, children = { group } })

	local built = contribution.attach(root, {
		handleActivate = function(path: string): boolean
			local leaf = string.match(path, "([^/]+)$")
			if leaf ~= nil and byId[leaf] ~= nil then
				choose(byId[leaf])
				return true
			end
			return false
		end,
	})

	local api = {}
	api.blueprint = built
	api.presentation = presentation
	--[[ THE ID THIS STRIP GAVE EACH OPTION, as `{ value, id }` pairs — the exact
		table the D4 indicator is handed, published because D5's TabView needs the
		same answer for a different job: `controller.scrollToVisible` takes a mounted
		PATH, and finding the node for a selection value means walking the mounted
		tree for that id. String arithmetic on "Opt1" is the assumption that breaks
		silently the day this control's internals move, so the id is published
		rather than guessed. Frozen: it describes what was built, and a caller that
		edited it would be editing what the indicator resolves against. ]]
	api.segments = table.freeze(segments)

	-- STILL SCHEMA /1 AFTER D6, deliberately. D6 only ADDS fields: every field
	-- that shipped keeps its name, its type and its meaning, so every reader
	-- written against /1 keeps working and a reader that wants the new facts asks
	-- for them by name. A bump would invalidate those readers to buy nothing — a
	-- schema string exists to warn about an INCOMPATIBLE shape, and there is not
	-- one here. (D4 added `indicator` and `axis` on the same reasoning.)
	function api.dump()
		local current = selected:get()
		local chosenLabel: string? = nil
		local chosenIcon: string? = nil
		for _, option in spec.options do
			if option.value == current then
				-- READ LIVE, never the build-time snapshot: a bound label is what
				-- the reference shells use to carry a terse thumb-zone name, and a
				-- dump that announced the name it was born with would report the
				-- wrong word for the whole second half of the session
				chosenLabel = labelNow(option)
				chosenIcon = option.icon
			end
		end
		return {
			schema = "facet-picker-dump/1",
			id = id,
			optionCount = #spec.options,
			requestedPresentation = requested,
			presentation = presentation:get(),
			-- WHERE THE ADAPTIVE FACT CAME FROM: "spec" (the author wired
			-- it), "core" (the surface's own environment answered, no wiring), or
			-- "none" (a declared presentation, which consults no ladder at all). A
			-- screen can be audited for adaptation it never had to author.
			sizeClassFrom = sizeClassFrom,
			axis = axis:get(),
			-- THE FIELD THAT TELLS THE TWO "y" SHAPES APART. A vertical pill and an
			-- inline row list both report `axis = "y"`; only this says which one is
			-- on screen, so a report of "the picker went full width" is answerable.
			verticalPill = verticalPill:get(),
			-- what was ASKED for beside what it resolved to, exactly as
			-- `requestedPresentation`/`presentation` already pair
			requestedIndicator = indicatorRequest,
			-- the D4 seam has no dump schema of its own (it is internal); its state
			-- is reported HERE, where a bug report about a bar in the wrong place
			-- already is
			indicator = if indicatorApi ~= nil then indicatorApi.state() else "none",
			iconOnly = iconOnly,
			iconCount = iconCount,
			-- D5: what the band is doing with its offer, and how many segments
			-- carry a count. `sizing` is the field a report of "the tab strip does
			-- not scroll" wants first — a `fill` strip cannot overflow, so it can
			-- never have anything to scroll.
			sizing = sizingNow(),
			badgeCount = badgeCount,
			selectedLabel = chosenLabel,
			selectedIcon = chosenIcon,
			-- ALWAYS the label, never the glyph: an icon-only segment's whole
			-- accessibility story is that `label` survived being undrawn
			semanticText = `{spec.label or "selection"}: {chosenLabel or "none"}`,
		}
	end

	function api.dispose()
		scope:dispose()
	end

	return api
end

return picker
