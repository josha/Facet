--!strict
-- Picker: single-selection from a small option set (docs/plans/swiftui-parity-next.md
-- investment 7; acceptance row B-DSP2). Two presentations over ONE selection model:
--
--   segmented — options side by side, always visible. Good for 2–4 short options.
--   inline    — options stacked as rows. Good for longer labels or more options.
--
-- The presentation is ADAPTIVE, not a platform branch: `presentation = "automatic"`
-- (the default) chooses from the option count and the available space class the
-- caller passes in, exactly as `LuauUI.adaptive` computes it. A device name never
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
-- neighbour wears a word. The HIG says the same thing about menus — "provide
-- icons for all menu items in a group, or none of them" — so a half-iconned
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

local controlContract = require("./contract")
local contribution = require("../input/contribution")
local selectionIndicator = require("./selection_indicator")
local specGuard = require("../spec_guard")

local picker = {}

-- `icon` is a SEMANTIC NAME ("close", "chevron.trailing", a namespaced
-- "ns:name"), never an asset id. `label` is required whatever is drawn.
export type Option = { value: any, label: string, icon: string? }

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
	-- "x" (default) | "y" — the SEGMENTED presentation's axis. "y" is a vertical
	-- PILL (f1's left rail), which is a different shape from the `inline` row list
	-- and deliberately does not overload it. Inert under `inline`, which is a
	-- column by definition.
	axis: string?,
	-- true makes the option ICON what every segment wears at every width, with
	-- `label` staying the semantic name (f1's icon-only pill and rail). Default
	-- false: the segment keeps its word and degrades to the glyph. A GROUP
	-- decision — see the header on why it cannot be per-option.
	iconOnly: boolean?,
	sizeClass: any?, -- string | Readable<string> from LuauUI.adaptive.conditions
	env: any?, -- optional environment, so the indicator's metrics follow a live theme
	enabled: any?,
	onChange: ((value: any) -> ())?,
}

local PRESENTATIONS: { [string]: boolean } = { automatic = true, segmented = true, inline = true }
local INDICATORS: { [string]: boolean } = { automatic = true, none = true, underline = true, pill = true }
local AXES: { [string]: boolean } = { x = true, y = true }

-- THE TWO CONTAINER SHAPES, hoisted so the memo below returns a STABLE table
-- rather than a fresh one per evaluation (a dimension compared by identity would
-- otherwise re-solve on every read).
--
--   band  the horizontal segmented control and the inline row list: both span
--         the offer, and the segments divide it.
--   rail  the VERTICAL pill: as wide as its widest segment and no wider (f1's
--         left rail), floored at the tap target because an icon-only rail's
--         natural width is a glyph — measured at 36px, which is under it.
local BAND_WIDTH = table.freeze({ type = "fill", weight = 1 })
local RAIL_WIDTH = table.freeze({ type = "minMax", min = "targetSizes.minimum" })

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

-- CLOSED SPEC (constitution §4; ARCH-1). Exactly the fields this control
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
})

function picker.build(LuauUI: any, core: any, spec: Spec)
	specGuard.assertKnownKeys("newPicker", spec, PICKER_KEYS, "spec")
	local UI = LuauUI.UI
	local id = spec.id or "Picker"
	local scope = core:scope("picker-" .. tostring(id))
	if type(spec.options) ~= "table" or #spec.options == 0 then
		error(`LuauUI newPicker('{id}'): \`options\` must be a non-empty array of value/label pairs`, 0)
	end
	local selected = spec.selected
	if type(selected) ~= "table" or (selected :: any).kind ~= "signal" then
		error(`LuauUI newPicker('{id}'): \`selected\` must be a SETTABLE Signal the caller owns`, 0)
	end
	local requested = spec.presentation or "automatic"
	if not PRESENTATIONS[requested] then
		error(`LuauUI newPicker('{id}'): unknown presentation '{requested}'. One of automatic | segmented | inline.`, 0)
	end
	local indicatorRequest = spec.indicator or "automatic"
	if not INDICATORS[indicatorRequest] then
		error(
			`LuauUI newPicker('{id}'): unknown indicator '{tostring(indicatorRequest)}'. `
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
	local segmentedAxis = spec.axis or "x"
	if not AXES[segmentedAxis] then
		error(
			`LuauUI newPicker('{id}'): unknown axis '{tostring(segmentedAxis)}'. One of x | y. `
				.. '`axis = "y"` is the VERTICAL segmented pill; the stacked row list is `presentation = "inline"`.',
			0
		)
	end

	-- ===== the option lint (D6) ===========================================
	-- Three authoring rules, all enforced here rather than left to be noticed on
	-- a screen: a segment always has a NAME, a group is all-iconned or none, and
	-- `iconOnly` needs something to draw.
	local longest = 0
	local iconCount = 0
	for index, option in spec.options do
		if type(option) ~= "table" then
			error(`LuauUI newPicker('{id}'): option {index} must be a table of value / label / optional icon`, 0)
		end
		if type(option.label) ~= "string" or option.label == "" then
			error(
				`LuauUI newPicker('{id}'): option {index} needs a non-empty \`label\`. It is the SEMANTIC name — `
					.. "what `dump().semanticText` announces and what an icon-only segment has instead of "
					.. "readable text. An icon with no name is unreadable to every non-visual consumer.",
				0
			)
		end
		if option.icon ~= nil then
			if type(option.icon) ~= "string" or option.icon == "" then
				error(
					`LuauUI newPicker('{id}'): option {index}'s \`icon\` must be a semantic icon NAME `
						.. '("close", "chevron.trailing", "ns:name"), never an asset id.',
					0
				)
			end
			iconCount += 1
		end
		longest = math.max(longest, #option.label)
	end
	if iconCount > 0 and iconCount < #spec.options then
		error(
			`LuauUI newPicker('{id}'): {iconCount} of {#spec.options} options carry an \`icon\`. Provide icons for `
				.. "all options in a group, or none of them (HIG: Menus) — a half-iconned group reads as a "
				.. "mistake at every width except the one it was authored at.",
			0
		)
	end
	if spec.iconOnly ~= nil and type(spec.iconOnly) ~= "boolean" then
		error(`LuauUI newPicker('{id}'): \`iconOnly\` must be a boolean`, 0)
	end
	local iconOnly = spec.iconOnly == true
	if iconOnly and iconCount == 0 then
		error(
			`LuauUI newPicker('{id}'): \`iconOnly\` was asked for but no option carries an \`icon\`, so there `
				.. "would be nothing to draw. Give every option an icon, or drop `iconOnly`.",
			0
		)
	end

	local function readSizeClass(use: any?): string?
		local sc = spec.sizeClass
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

	-- the contract's one reading of `enabled` (a one-shot read: never subscribes)
	local function isEnabled(): boolean
		return controlContract.enabledNow(spec.enabled)
	end

	local function choose(value: any): boolean
		if not isEnabled() or selected:get() == value then
			return false
		end
		selected:set(value)
		if spec.onChange ~= nil then
			spec.onChange(value)
		end
		return true
	end

	-- one row per option. Without an indicator, `selected` is a BINDING prop that
	-- rides a style tag; WITH one, the indicator is the selection paint and the
	-- buttons go plain so nothing paints over the chip behind them (see header).
	local slides = indicator ~= "none"
	local rows: { any } = {}
	local byId: { [string]: any } = {}
	local segments: { any } = {}
	for i, option in spec.options do
		local optionId = "Opt" .. i
		byId[optionId] = option.value
		table.insert(segments, { value = option.value, id = optionId })
		table.insert(
			rows,
			UI.Button({
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
				surface = if slides then "plain" else nil,
				selected = if slides
					then nil
					else scope:own(core:memo(function(use)
						return use(selected) == option.value
					end)),
				-- CROSS-AXIS ON THE RAIL, main-axis in the band. Either way `fill`
				-- is what makes every segment the same size: it divides the band,
				-- and it stretches each segment to the rail's resolved width.
				width = { type = "fill", weight = 1 },
				height = { type = "minMax", min = "targetSizes.minimum" },
			})
		)
	end

	-- ONE class with a reactive axis, so a presentation flip is a re-solve and the
	-- option buttons keep their identity, focus and state (the A-AL2 rule).
	-- `axis = "y"` on the SEGMENTED presentation is the vertical PILL; `inline` is
	-- a column by definition and ignores it.
	local axis = scope:own(core:memo(function(use)
		return if use(presentation) == "segmented" then segmentedAxis else "y"
	end))

	-- ...and the fact `axis` alone CANNOT express, because the vertical pill and
	-- the inline row list both answer "y". Two names for two facts is the whole
	-- guard against confusing them; it also drives the container shape below and
	-- is reported by `dump()`.
	local verticalPill = scope:own(core:memo(function(use)
		return use(presentation) == "segmented" and segmentedAxis == "y"
	end))

	-- the RAIL hugs (floored at the tap target); the band and the row list fill.
	-- Reactive because `verticalPill` is: an adaptive picker that flips out of
	-- segmented must give the offer back, and a build-time width would leave a
	-- 44px column standing where a full-width row list belongs.
	local groupWidth = scope:own(core:memo(function(use)
		return if use(verticalPill) then RAIL_WIDTH else BAND_WIDTH
	end))

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
		indicatorApi = selectionIndicator.build(LuauUI, core, {
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
				chosenLabel = option.label
				chosenIcon = option.icon
			end
		end
		return {
			schema = "luauui-picker-dump/1",
			id = id,
			optionCount = #spec.options,
			requestedPresentation = requested,
			presentation = presentation:get(),
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
