--!strict
local Compose = require("../vendor/compose/core")
local ownedBuild = require("../core/owned_build")
-- Picker presents one selection model as a menu, a segmented strip or rows.
-- The automatic style follows available space, input and viewing distance.
-- Static and keyed strips use Compose ownership; their controls retain Facet's
-- focus, selection validation, themes and layout rules.
local chrome_slots = require("../tokens/chrome_slots")
local controlContract = require("../class_contract")
local contribution = require("../input/contribution")
local selectionIndicator = require("./selection_indicator")
local specGuard = require("../spec_guard")
local styling = require("../tokens/styling")
local surfaceEnv = require("../env/surface_env")

local selectionModel = require("../selection_model")
local menuRecipe = require("./menu_recipe")
local themeSnapshot = require("../themes/snapshot")
local textMetrics = require("../layout/text_metrics")
local fieldChrome = require("./field_chrome")
local vocabulary = require("./control_vocabulary")
local picker = {}

-- `icon` is a SEMANTIC NAME ("close", "chevron.trailing", a namespaced
-- "ns:name"), never an asset id. `label` is required whatever is drawn, and may
-- be a string or a Readable of one (D5: the reference shells flip between a full
-- and a terse localized name live). `badge` is the count seal — a string, a
-- number, or a Readable of either; an empty one hides the plate rather than
-- painting an empty bubble.
local specTypes = require("../spec_types/picker")
type AnyCell = specTypes.AnyCell
export type Option = specTypes.Option

export type Spec<V = AnyCell> = specTypes.Spec<V>

local PRESENTATIONS: { [string]: boolean } = { automatic = true, segmented = true, inline = true, radio = true }
-- the PUBLIC style names, and the strip builder's own vocabulary for the three
-- that are strips (`radioGroup` is the row list wearing a radio mark)
local STYLES: { [string]: boolean } = {
	automatic = true,
	menu = true,
	segmented = true,
	inline = true,
	radioGroup = true,
	navigationLink = true,
	cards = true,
}
local STYLE_LIST = "automatic | menu | segmented | inline | radioGroup | navigationLink | cards"
local STRIP_NAME: { [string]: string } = { segmented = "segmented", inline = "inline", radioGroup = "radio" }
local PUBLIC_NAME: { [string]: string } = { segmented = "segmented", inline = "inline", radio = "radioGroup" }
local pickerMenu = require("./picker_menu")
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

--[[ ===== THE STRIP IS ONE STRIP (user visual review 2026-09-12, item 2) =====

	A segmented control used to be a fully-rounded track holding fully-rounded
	segments held apart by an `xs` gap. Beside a page whose every other box wears
	`radii.control` that reads as a row of DISCONNECTED CHIPS rather than one
	control with one value, and it is the one shape a theme package could not
	restyle (see `selection_indicator.DEFAULT_CORNER`).

	It is one strip now, and the rule is the same three sentences on both axes:

	  * only the OUTER ends round, with `radii.control` — so a package whose
	    control radius is fully round still gets a capsule and a square package
	    gets a square;
	  * the inner segments are square and TOUCH, separated by a hairline seam
	    rather than by air;
	  * the selection fill wears the shape of the segment it is on, which is what
	    `selection_indicator.segmentCorners` exists for.

	The radius is spent as a TOKEN, never a number: `normalizeCorners` keeps the
	name beside the authored pixel and the painter re-resolves it against the
	style it paints with, so a ten-foot display's derived radius reaches the
	strip and a build-time number never freezes the near one in (the paint-family
	lockstep rule). ]]
local SEGMENT_RADIUS = selectionIndicator.TRACK_CORNER
-- the per-corner data for segment `index` of `count` along `axis`, ASKED rather
-- than re-derived: the level picker's run of marks speaks the same three
-- sentences, and one of the two copies would be the one that stopped being true
local stripCorners = selectionIndicator.segmentShape

--[[ THE SEAM'S OWN MAIN-AXIS SIZE, and it is what makes the gap unnecessary.
	The `Options` stack of a tracked strip runs at `gap = 0` and the seam between
	each pair of segments carries ALL the spacing: a hairline while the strip is
	a segmented track (segments touch, with one rule between them), and the
	ordinary `xs` step while the same stack is a row list (an adaptive picker
	flips between the two as a RE-SOLVE, so the separators are mounted in both).
	One reactive dimension instead of a `When` per seam, which would have made
	the strip structural and put the indicator's own segment-id check to sleep. ]]
local SEAM_HAIRLINE = table.freeze({ type = "fixed", px = "strokes.hairline" })
local SEAM_ROW_GAP = table.freeze({ type = "fixed", px = "space.xs" })
local SEAM_CROSS = table.freeze({ type = "fill", weight = 1 })
-- ...and the seam is INSET off the segment's full extent, so it reads as a
-- divider between two labels rather than a wall between two boxes
local SEAM_MARGIN_X = table.freeze({ top = "xs", bottom = "xs" })
local SEAM_MARGIN_Y = table.freeze({ left = "xs", right = "xs" })
-- the count seal's own box. Both numbers are theme SPACING steps, so a package
-- published before this existed answers them and a theme that retunes its
-- spacing retunes the badge with it (the `selection_indicator` precedent).

-- the adaptive rule, pure and exported so a caller can predict it
function picker.resolvePresentation(
	optionCount: number,
	sizeClass: string?,
	longestLabel: number,
	hasDescription: boolean?,
	fits: boolean?
): string
	--[[ A SEGMENT CARRIES A LABEL AND NOTHING ELSE (visual review 2026-09-11): an
		option with a `description` is a ROW, and a strip whose natural band no
		longer fits its offer at the current text size is a row list too — never a
		pill that grows uneven segments. `fits` is a fact the caller measured
		(nil = unknown, read as "fits", which is what every caller before this
		round asked). ]]
	if hasDescription == true or fits == false then
		return "inline"
	end
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

--[[ THE AUTOMATIC STYLE, as a pure function of facts (see the header). Exported
	so a screen can predict what it will get, and pinned by tests/picker_style. ]]
export type StyleFacts = specTypes.StyleFacts
function picker.resolveStyle(facts: StyleFacts): string
	if facts.searchable == true then
		return "navigationLink"
	end
	--[[ A STRIP THAT CANNOT FIT ITS ROW never becomes a pill (2026-09-11):
		`resolvePresentation` answers the row list for it, and the ladder below
		keeps that answer where rows are the idiom (a ten-foot display, a nearby
		pad on a roomy screen) and folds it into the menu everywhere else —
		squeezed segments would truncate their labels. ]]
	local strip = picker.resolvePresentation(
		facts.optionCount,
		facts.sizeClass,
		facts.longestLabel,
		facts.hasDescription,
		facts.fits
	)
	-- a row list is a strip only while it stays short; past the popover limit
	-- the rows would be a page of their own, and a menu holds them instead
	local rows = if facts.optionCount <= menuRecipe.PICKER_POPOVER_LIMIT then strip else "menu"
	if facts.distanceProfile == "ten-foot" then
		return rows
	end
	if facts.primaryInput == "gamepad" then
		if strip == "segmented" then
			return "segmented"
		end
		return if facts.sizeClass == "compact" then "menu" else rows
	end
	return "menu"
end

-- CLOSED SPEC (constitution §4). Exactly the fields this control
-- reads — an unknown one is an authoring mistake, never a silent no-op.
local PICKER_KEYS = specGuard.keySet({
	"style",
	"query",
	"placeholder",
	"required",
	"onChanging",
	"axis",
	"enabled",
	"env",
	"id",
	"iconOnly",
	"indicator",
	"label",
	"valueAlignment",
	"onChange",
	"options",
	"presentation",
	"selected",
	"sizeClass",
	"sizing",
	"textSize",
	-- `track = false` marks a TAB STRIP inside its own band (TabView): no
	-- segmented plate, no carved inset, no disclose plate — the band's own
	-- ladder owns all three
	"track",
	--[[ ...and when the band owns the plate, the band also owns the SHAPE the
		selected fill has to match (owner report 2026-09-12). A corner token name
		(or a Readable of one) naming what the strip around this picker actually
		wears; `selection_indicator.fillCornerFor` derives the fill's silhouette
		from it. Only a `track = false` caller has anything to say here — a tracked
		picker draws its own plate and this control already knows its corner. ]]
	"stripCorner",
	-- the shared field furniture and local vocabulary
	"hint",
	"errorText",
	"requiredMark",
	"controlSize",
	"appearance",
	"corners",
	-- the menu panel's bound, chrome included
	"maxHeight",
	-- the radio group's mark: "leading" (default) | "trailing"
	"indicatorPosition",
})

--[[ ONE APPEARANCE WORD, TWO FAMILIES. The menu trigger speaks
	standard/contrast/utility and the segmented strip filled/stroke/utility; an
	automatic picker accepts all five and maps each onto whichever family is on
	screen (standard|filled, contrast|stroke, utility), so a family switch never
	drops the author's intent. Absent stays absent: each family keeps its own
	default. Row forms (inline, radioGroup, cards) take no appearance. ]]
local MENU_WORDS = table.freeze({ "standard", "contrast", "utility" })
local STRIP_WORDS = table.freeze({ "filled", "stroke", "utility" })
local AUTO_WORDS = table.freeze({ "standard", "contrast", "filled", "stroke", "utility" })
local TO_MENU: { [string]: string } =
	{ standard = "standard", filled = "standard", contrast = "contrast", stroke = "contrast", utility = "utility" }
local TO_STRIP: { [string]: string } =
	{ standard = "filled", filled = "filled", contrast = "stroke", stroke = "stroke", utility = "utility" }
local function wordsFor(style: string): { string }?
	if style == "automatic" then
		return AUTO_WORDS
	elseif style == "menu" or style == "navigationLink" then
		return MENU_WORDS
	elseif style == "segmented" then
		return STRIP_WORDS
	end
	return nil
end

-- read a Readable-or-plain value, subscribing when a `use` is in hand. BOTH
-- reactive kinds, exactly as `selection_indicator.readValue` does and for the
-- same reason: `axis`/`sizing` arrive as a Signal from a test and as a MEMO from
-- a TabView whose placement is derived, and reading only one kind hands the
-- caller back the node itself.
local readValue = require("../selection_model").read

local OPTION_KEYS = specGuard.keySet({
	"id",
	"value",
	"label",
	"description",
	"icon",
	"badge",
	"enabled",
	"sectionTitle",
	"avatar",
	"meta",
})
local function validateArray(list)
	assert(type(list) == "table", "Picker: options must be an array")
	local count = 0
	for index in list do
		assert(
			type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #list,
			"Picker: options must be a dense array"
		)
		count += 1
	end
	assert(count == #list, "Picker: options must be a dense array")
end
local function validateOption(option, use)
	assert(type(option) == "table", "Picker: each option must be a table")
	specGuard.assertKnownKeys("Picker.option", option, OPTION_KEYS, "option")
	assert(option.value ~= nil and option.value == option.value, "Picker: each option needs a non-NaN value")
	local label = readValue(option.label, use)
	assert(type(label) == "string" and label ~= "", "Picker: each option needs a non-empty label (its semantic name)")
	local description = readValue(option.description, use)
	assert(
		description == nil or type(description) == "string",
		"Picker: description must be a string or readable string"
	)
	local badge = readValue(option.badge, use)
	assert(
		badge == nil or type(badge) == "string" or type(badge) == "number",
		"Picker: badge must be a string or number or readable of either"
	)
	local enabled = readValue(option.enabled, use)
	assert(enabled == nil or type(enabled) == "boolean", "Picker: option enabled must be boolean or readable boolean")
	local heading = readValue(option.sectionTitle, use)
	assert(heading == nil or type(heading) == "string", "Picker: sectionTitle must be a string or readable string")
	local meta = readValue(option.meta, use)
	assert(meta == nil or type(meta) == "string", "Picker: meta must be a string or readable string")
	assert(
		option.icon == nil or (type(option.icon) == "string" and option.icon ~= ""),
		"Picker: icon must be a non-empty semantic icon name"
	)
	assert(
		option.id == nil
			or (type(option.id) == "string" and option.id ~= "" and not string.find(option.id, "/", 1, true)),
		"Picker: option id must be a non-empty path-safe string"
	)
end

-- Live arrays use keyed rows: identity follows the supplied id, while selection
-- follows value. Removing a row never reconciles the caller's selected signal.
--[[ THE TRACK'S CARVED BORDER IS THE SEGMENTS' INSET (themed containment,
	item 8, 2026-09-11). A nine-slice `control` plate carves a border its
	content must sit inside; the plate is a SIBLING of the segments (so no
	segment path moves), so the segments take the same inset as padding —
	reactively, because a theme swap re-carves it and a flip to a row form
	takes the plate away. Nothing is read without an environment (a declared
	strip with none stays flat, as the neutral package carves nothing). ]]
local function trackPaddingFor(core: any, spec: any, presentation: any): any
	local env = surfaceEnv.forSpec(core, spec.env)
	if env == nil then
		return nil
	end
	return function(use)
		if use(presentation) ~= "segmented" then
			return 0
		end
		local metrics = use(env:get("themeMetrics"))
		local insets = if type(metrics) == "table" then (metrics :: any).chromeInsets else nil
		local plate = if type(insets) == "table" then insets.control else nil
		if type(plate) ~= "table" then
			return 0
		end
		return {
			top = tonumber(plate.top) or 0,
			right = tonumber(plate.right) or 0,
			bottom = tonumber(plate.bottom) or 0,
			left = tonumber(plate.left) or 0,
		}
	end
end

local function buildLiveOwned(Facet, core, spec, requested: string, onReselect, owner)
	local UI = Facet.UI
	local id = spec.id or "Picker"
	assert(selectionModel.isWritable(spec.selected), "UI.Picker: selected must be a writable Compose cell")
	assert(PRESENTATIONS[requested], "Picker: presentation must be automatic | segmented | inline | radio")
	assert(spec.indicator == nil or INDICATORS[spec.indicator], "Picker: invalid live indicator")
	local slides = requested == "segmented" and (spec.indicator == "pill" or spec.indicator == "underline")
	local mountedNode
	local function key(option)
		return option.id or tostring(option.value)
	end
	local function validateOptions(list, use)
		validateArray(list)
		local ids, values = {}, {}
		local icons = 0
		for _, option in list do
			validateOption(option, use)
			local identity = key(option)
			assert(
				type(identity) == "string" and identity ~= "" and not string.find(identity, "/", 1, true),
				"Picker: option identities must be path-safe"
			)
			assert(not ids[identity] and not values[option.value], "Picker: duplicate option identity or value")
			ids[identity] = true
			values[option.value] = true
			if option.icon ~= nil then
				icons += 1
			end
		end
		assert(icons == 0 or icons == #list, "Picker: provide icons for all options or none")
		assert(not spec.iconOnly or icons == #list, "Picker: iconOnly requires an icon for every option")
		return list
	end
	validateOptions(readValue(spec.options))
	local options = Compose.formula(function(use)
		return validateOptions(readValue(spec.options, use), use)
	end)
	options:peek()
	local env = spec.env
	if requested == "automatic" and not spec.sizeClass then
		env = surfaceEnv.resolve("UI.Picker", id, core, env, "automatic selection adapts to available space")
	end
	local presentation = Compose.formula(function(use)
		if requested ~= "automatic" then
			return requested
		end
		local list = use(options)
		local longest = 0
		for _, option in list do
			longest = math.max(longest, #readValue(option.label, use))
		end
		local described = false
		for _, option in list do
			if readValue(option.description, use) ~= nil then
				described = true
				break
			end
		end
		local source: any = (spec :: any)._presentationSource
		if source ~= nil then
			local resolved = use(source)
			return if resolved == "radioGroup" then "radio" else resolved
		end
		return picker.resolvePresentation(
			#list,
			readValue(spec.sizeClass or env:get("sizeClass"), use),
			longest,
			described
		)
	end)
	local axis = Compose.formula(function(use)
		return if use(presentation) == "inline" or use(presentation) == "radio"
			then "y"
			else (readValue(spec.axis, use) or "x")
	end)
	local function sizingNow(use)
		local value = readValue(spec.sizing, use)
		return if SIZINGS[value] then value else "fill"
	end
	local verticalPill = Compose.formula(function(use)
		return use(presentation) == "segmented" and use(axis) == "y"
	end)
	local groupWidth = Compose.formula(function(use)
		return if use(verticalPill) then RAIL_WIDTH elseif sizingNow(use) == "hug" then NATURAL_WIDTH else BAND_WIDTH
	end)
	local segmentWidth = Compose.formula(function(use)
		return if use(verticalPill) or sizingNow(use) == "fill" then SEGMENT_FILL else SEGMENT_NATURAL
	end)
	local function choose(identity)
		if
			owner.isDisposed()
			or controlContract.isDisabled(mountedNode)
			or not controlContract.enabledNow(spec.enabled)
		then
			return
		end
		local option
		for _, item in options:peek() do
			if key(item) == identity then
				option = item
				break
			end
		end
		if not option then
			return
		end
		local accepted, nextValue = selectionModel.choose(
			options:peek(),
			readValue(spec.selected),
			option.value,
			spec.required,
			spec.onChanging
		)
		if
			accepted
			and not owner.isDisposed()
			and not controlContract.isDisabled(mountedNode)
			and controlContract.enabledNow(spec.enabled)
		then
			core.reactor:batch(function()
				spec.selected:set(nextValue)
				if spec.onChange then
					spec.onChange(nextValue)
				end
			end)
		end
	end
	-- a heading is its own keyed entry, so one can arrive after mount without
	-- re-keying the row under it; it shows only on a stacked (y) list
	local rows = UI.ForEach({
		id = "Rows",
		items = Compose.formula(function(use)
			return menuRecipe.sectionEntries(use(options), key, use)
		end),
		key = function(entry)
			return if entry.sectionHeading ~= nil then entry.key else key(entry)
		end,
		row = function(initial, _, current)
			if initial.sectionHeading ~= nil then
				return UI.When({
					id = "SectionHeading",
					condition = function(use)
						return use(axis) == "y"
					end,
					thenView = function()
						return menuRecipe.sectionHeading(UI, function(use)
							return use(current).sectionHeading
						end)
					end,
				})
			end
			local identity = key(initial)
			-- Compose supplies the current record for this key. Each row reads
			-- that record directly instead of searching the entire option list.
			local function prop(name, fallback)
				return function(use)
					local value = readValue(use(current)[name], use)
					return if value == nil then fallback else value
				end
			end
			local selected = function(use)
				return selectionModel.read(spec.selected, use) == use(current).value
			end
			local enabled = function(use)
				return controlContract.enabledIn(use, spec.enabled)
					and controlContract.enabledIn(use, use(current).enabled)
			end
			local row = menuRecipe.row(UI, {
				id = "Option-" .. identity,
				wrap = true,
				surface = if slides then "plain" else nil,
				labelTint = if slides and spec.indicator == "pill"
					then function(use)
						return { role = if selected(use) then "onAccent" else "content", blend = 1 }
					end
					else nil,
				label = prop("label"),
				description = prop("description", ""),
				icon = prop("icon"),
				badge = prop("badge", ""),
				width = segmentWidth,
				textSize = spec.textSize,
				iconOnly = spec.iconOnly,
				selected = if slides then nil else selected,
				enabled = enabled,
				indicator = if requested == "radio" then "radio" else nil,
				indicatorEdge = spec.indicatorPosition,
				height = if spec.controlSize ~= nil
					then vocabulary.metricPath(readValue(spec.controlSize), "height")
					else nil,
				markHidden = function(use)
					return not selected(use)
				end,
			})
			row = contribution.attach(row, {
				handleActivate = function()
					if onReselect and readValue(spec.selected) == readValue(current).value and readValue(enabled) then
						onReselect()
					else
						choose(identity)
					end
					return true
				end,
			})
			return row
		end,
	})
	local group = UI.AdaptiveStack({
		id = "Options",
		axis = axis,
		gap = "xs",
		width = groupWidth,
		padding = if slides and (spec :: any).track ~= false then trackPaddingFor(core, spec, presentation) else nil,
		children = { rows },
	})
	local indicatorApi
	if slides then
		local segments = Compose.formula(function(use)
			local out = {}
			for _, option in use(options) do
				table.insert(out, { id = "Option-" .. key(option), value = option.value })
			end
			return out
		end)
		indicatorApi = selectionIndicator.build(Facet, core, {
			id = "Indicator",
			content = group,
			segments = segments,
			selected = spec.selected,
			skin = spec.indicator,
			axis = axis,
			env = spec.env,
			width = groupWidth,
			-- the container the fill has to match; see the other build site below
			trackCorner = if (spec :: any).track == false then (spec :: any).stripCorner else SEGMENT_RADIUS,
		})
		owner.own(function()
			indicatorApi:dispose()
		end)
		group = indicatorApi.blueprint
	end
	local children = { group }
	if spec.label then
		table.insert(children, 1, UI.Text({ id = "Label", text = spec.label, textSize = "label", width = UI.fill() }))
	end
	local blueprint = contribution.attach(UI.VStack({ id = id, width = groupWidth, gap = "xs", children = children }), {
		syncGeometry = function(_, node)
			mountedNode = node
		end,
	})
	local function dump()
		return {
			schema = "facet-picker-dump/1",
			id = id,
			selected = readValue(spec.selected),
			presentation = presentation:peek(),
			axis = axis:peek(),
			sizing = sizingNow(),
			iconOnly = spec.iconOnly == true,
			optionCount = #options:peek(),
			indicator = if indicatorApi then indicatorApi.state() else nil,
		}
	end
	return {
		blueprint = blueprint,
		presentation = presentation,
		dump = dump,
		dispose = function()
			owner.dispose()
		end,
	}
end

local function buildLive(Facet, core, spec, requested, onReselect)
	return ownedBuild(core, function(owner)
		return buildLiveOwned(Facet, core, spec, requested, onReselect, owner)
	end)
end

-- ===== the option lint (D6), shared by every style =========================
-- Three authoring rules, all enforced at BUILD rather than left to be noticed
-- on a screen — and enforced before the style is chosen, so an automatic
-- picker that resolves the menu family refuses the same half-iconned group the
-- strip would: a segment always has a NAME, a group is all-iconned or none, and
-- `iconOnly` needs something to draw. Returns the measured facts the strip
-- builder spends.
local function lintStaticOptions(spec: Spec, id: string): any
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
	local optionIds, optionValues = {}, {}
	local hasDescription = false
	for index, option in spec.options do
		validateOption(option)
		if option.description ~= nil then
			hasDescription = true
		end
		local optionId = option.id or "Opt" .. index
		assert(not optionIds[optionId] and not optionValues[option.value], "Picker: duplicate option identity or value")
		optionIds[optionId] = true
		optionValues[option.value] = true
		if type(option) ~= "table" then
			error(`Facet UI.Picker('{id}'): option {index} must be a table of value / label / optional icon`, 0)
		end
		local labelText = labelNow(option)
		if type(labelText) ~= "string" or labelText == "" then
			error(
				`Facet UI.Picker('{id}'): option {index} needs a non-empty \`label\`. It is the SEMANTIC name — `
					.. "what `dump().semanticText` announces and what an icon-only segment has instead of "
					.. "readable text. An icon with no name is unreadable to every non-visual consumer.",
				0
			)
		end
		if option.badge ~= nil then
			local badgeText = readValue(option.badge)
			if type(badgeText) ~= "string" and type(badgeText) ~= "number" then
				error(
					`Facet UI.Picker('{id}'): option {index}'s \`badge\` must be a string or a number (or a `
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
					`Facet UI.Picker('{id}'): option {index}'s \`icon\` must be a semantic icon NAME `
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
			`Facet UI.Picker('{id}'): {iconCount} of {#spec.options} options carry an \`icon\`. Provide icons for `
				.. "all options in a group, or none of them — a half-iconned group reads as a "
				.. "mistake at every width except the one it was authored at.",
			0
		)
	end
	if spec.iconOnly ~= nil and type(spec.iconOnly) ~= "boolean" then
		error(`Facet UI.Picker('{id}'): \`iconOnly\` must be a boolean`, 0)
	end
	local iconOnly = spec.iconOnly == true
	if iconOnly and iconCount == 0 then
		error(
			`Facet UI.Picker('{id}'): \`iconOnly\` was asked for but no option carries an \`icon\`, so there `
				.. "would be nothing to draw. Give every option an icon, or drop `iconOnly`.",
			0
		)
	end
	return {
		longest = longest,
		iconCount = iconCount,
		badgeCount = badgeCount,
		iconOnly = iconOnly,
		labelNow = labelNow,
		hasDescription = hasDescription,
	}
end

local function buildStripOwned(Facet: any, core: any, spec: Spec, requested: string, onReselect, owner)
	local UI = Facet.UI
	local id = spec.id or "Picker"
	local mountedNode
	if type(spec.options) ~= "table" or #spec.options == 0 then
		error(`Facet UI.Picker('{id}'): \`options\` must be a non-empty array of value/label pairs`, 0)
	end
	validateArray(spec.options)
	local selected = spec.selected
	if not selectionModel.isWritable(selected) then
		error(`Facet UI.Picker('{id}'): \`selected\` must be a writable Compose cell the caller owns`, 0)
	end
	local indicatorRequest = spec.indicator or "automatic"
	if not INDICATORS[indicatorRequest] then
		error(
			`Facet UI.Picker('{id}'): unknown indicator '{tostring(indicatorRequest)}'. `
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
		elseif requested == "inline" or requested == "radio" then "none"
		else "pill"
	-- `axis` and `sizing` may each be a plain string or a Readable (see the Spec
	-- comments). The CURRENT value of a Readable is validated here too, so a typo
	-- is still an authoring error rather than a wrong edge — but a later unknown
	-- value degrades to the default rather than throwing from inside a memo,
	-- which is `selection_indicator.axisNow`'s own tolerance for a reactive enum.
	-- the radio group stacks by default (api.md: "Radio defaults to y"), the
	-- same answer the live-options builder gives it; a horizontal radio row is
	-- an authored `axis = "x"`
	local axisSource = if spec.axis == nil then (if requested == "radio" then "y" else "x") else spec.axis
	local function axisNow(use: any?): string
		local value = readValue(axisSource, use)
		return if AXES[value] then value else "x"
	end
	if not AXES[readValue(axisSource)] then
		error(
			`Facet UI.Picker('{id}'): unknown axis '{tostring(readValue(axisSource))}'. One of x | y. `
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
			`Facet UI.Picker('{id}'): unknown sizing '{tostring(readValue(sizingSource))}'. One of fill | hug. `
				.. "`fill` divides the offer among the segments (and therefore can never overflow); `hug` gives "
				.. "the band and every segment its natural width, which is what an overflowing tab strip is.",
			0
		)
	end

	local lint = lintStaticOptions(spec, id)
	local longest, iconCount, badgeCount, iconOnly = lint.longest, lint.iconCount, lint.badgeCount, lint.iconOnly
	local labelNow = lint.labelNow

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
			surfaceEnv.resolve("UI.Picker", id, core, spec.env, "an automatic presentation adapts to the size class")
		sizeClassSource = env:get("sizeClass")
		sizeClassFrom = source
	end

	local function readSizeClass(use: any?): string?
		local sc = sizeClassSource
		if sc == nil then
			return nil
		end
		if type(sc) == "table" then
			return readValue(sc, use)
		end
		return sc :: string
	end

	--[[ ONE LADDER, NOT TWO. The automatic wrapper (`buildAutomatic`) already
		resolved the style from the published facts, the option shapes and the
		measured offer; the strip it mounts follows THAT answer through
		`_presentationSource` rather than re-deriving a second one from fewer
		facts, which is how a wrapper could say "inline" while its strip drew a
		pill. A declared strip resolves for itself, as it always did. ]]
	local presentationSource: any = (spec :: any)._presentationSource
	local presentation = Compose.formula(function(use)
		if requested ~= "automatic" then
			return requested
		end
		if presentationSource ~= nil then
			local resolved = use(presentationSource)
			return if resolved == "radioGroup" then "radio" else resolved
		end
		return picker.resolvePresentation(#spec.options, readSizeClass(use), longest, lint.hasDescription)
	end)

	-- ONE class with a reactive axis, so a presentation flip is a re-solve and the
	-- option buttons keep their identity, focus and state (the A-AL2 rule).
	-- `axis = "y"` on the SEGMENTED presentation is the vertical PILL; `inline` is
	-- a column by definition and ignores it.
	local axis = Compose.formula(function(use)
		return if use(presentation) == "segmented" or use(presentation) == "radio" then axisNow(use) else "y"
	end)

	-- ...and the fact `axis` alone CANNOT express, because the vertical pill and
	-- the inline row list both answer "y". Two names for two facts is the whole
	-- guard against confusing them; it also drives the container shape below and
	-- is reported by `dump()`.
	local verticalPill = Compose.formula(function(use)
		return use(presentation) == "segmented" and axisNow(use) == "y"
	end)

	-- the RAIL hugs (floored at the tap target); a HUGGING band takes its natural
	-- width; the filling band and the row list take the offer. Reactive because
	-- all three inputs are: an adaptive picker that flips out of segmented must
	-- give the offer back, and a tab bar that moves from a bottom band to a
	-- centered cluster must stop filling — a build-time width would leave a 44px
	-- column standing where a full-width row list belongs.
	local groupWidth = Compose.formula(function(use)
		if use(verticalPill) then
			return RAIL_WIDTH
		end
		return if sizingNow(use) == "hug" then NATURAL_WIDTH else BAND_WIDTH
	end)

	-- the SEGMENT's own width, and it is a different question from the group's.
	-- On the rail this is the CROSS axis, where `fill` is what makes every segment
	-- share the rail's one resolved width; in a filling band it is the main axis,
	-- where `fill` divides the offer equally. Only a HUGGING band lets a segment
	-- take its own word's width — which is what makes "For you" wider than
	-- "Charts", and what a strip has to do before it can overflow at all.
	local segmentWidth = Compose.formula(function(use)
		if use(verticalPill) then
			return SEGMENT_FILL
		end
		return if sizingNow(use) == "hug" then SEGMENT_NATURAL else SEGMENT_FILL
	end)

	-- the contract's one reading of `enabled` (a one-shot read: never subscribes)
	local function isEnabled(): boolean
		return not owner.isDisposed()
			and not controlContract.isDisabled(mountedNode)
			and controlContract.enabledNow(spec.enabled)
	end

	local function choose(value: any): boolean
		if not isEnabled() then
			return false
		end
		local accepted = selectionModel.choose(spec.options, readValue(selected), value, spec.required, spec.onChanging)
		if not isEnabled() or not accepted then
			return false
		end
		core.reactor:batch(function()
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

	--[[ ...AND A PLATE UNDER A LABEL OWES THAT LABEL A COLOUR (stabilization B'1,
		2026-09-07). Going plain stops the option painting OVER the chip; it does
		not tell the option's own label what it is now sitting ON. It kept
		`TextButton { TextColor3 = $Content }` — the colour chosen to read on
		$Surface — while the chip filled with $Accent. Measured on Classic Desktop:
		1.55:1 on Day, 1.95:1 on Night, against a 4.5 floor. Facet Neutral passed
		at 4.82:1 by coincidence of that one palette, which is why it shipped.

		`role = "onIndicator"` is the label-only Button role (blueprint_schema, and
		the `Indicator label` rule in `tokens/sheet_model`): it names $OnAccent, the
		theme contract's one GATED partner for $Accent, and brings no fill — so the
		chip behind the option is still the only plate on screen.

		WHICH SKIN OWES IT is `selection_indicator.barSurfaceFor`, asked rather than
		re-derived: the pill plates with `accent`, the underline plates with nothing
		(it is a tint rule on one edge, and its label sits on the ordinary surface),
		and a caller that hands the seam a different plate gets nothing here because
		every other surface's label colour already IS $Content. ]]
	local platedRole: string? = nil
	if slides and selectionIndicator.barSurfaceFor(indicator, nil) == "accent" then
		platedRole = chrome_slots.ON_INDICATOR_ROLE
	end

	--[[ A TRACKED STRIP is the one this round's shape language is about: a plated
		track holding segments that touch. `track = false` is a TAB BAR inside its
		own band (TabView), which keeps its own spacing and its own ladder — so it
		takes the theme radius (item 6) and nothing else here. ]]
	local tracked = slides and (spec :: any).track ~= false
	local segmentCount = #spec.options
	-- the row form's silhouette, and the ONE shape both its states wear (item 5):
	-- the plate a theme paints under a chosen row is the row's own node, so an
	-- authored corner makes chosen and unchosen the same outline by construction
	-- the strip's outer corner: `corners` names it, absent is the theme's radius
	local outerCorner: any = if spec.corners == "pill"
		then "pill"
		elseif spec.corners == "square" then 0
		else SEGMENT_RADIUS
	local rowCorners = UI.cornersData(outerCorner)
	local trackOutline = UI.strokeData({ color = "hairline", thickness = "hairline", transparency = 0 })
	-- a named rung's segment and row height; the whole strip reserves the floor
	local rungHeight = vocabulary.deriveSize("UI.Picker", spec.controlSize, vocabulary.heightFor)
	local segmentHeight = rungHeight or SEGMENT_HEIGHT
	local rungPadding = vocabulary.deriveSize("UI.Picker", spec.controlSize, vocabulary.paddingFor)
	-- the three silhouettes a segment can wear, filled per index below: the
	-- horizontal strip's, the vertical rail's, and the row list's
	local cornersX: { any } = {}
	local cornersY: { any } = {}
	local cornersRow: { any } = {}

	--[[ ===== THE TEN-FOOT ROW LIFT (user visual review 2026-09-12, item 5) =====

		Across a room, the row a player is ON has to be readable as the row they
		are on from the sofa — and a selection tag is a colour change at ten feet.
		The focused row therefore LIFTS by a paint-only 1.05, the same envelope
		and the same spring class `button.luau`'s image form already uses.

		THE BOUNDARY IS THE WHOLE POINT: `scale` is in the presentation channel,
		so the solver never sees it, the box does not move, the hit target does
		not move and the focus order does not move. The rows are held apart by
		their own `xs` gap, which is wider than the 2.5% a 1.05 lift adds to one
		side of one row — `tests/selection_shape.spec.luau` pins that no row's
		PRESENTED VISUAL RECT reaches its neighbour while one is lifted, rather
		than leaving the arithmetic asserted.

		Reduced motion needs no branch: a `clock:spring` is decorative, and the
		motion authority places a decorative target at its terminus on the same
		frame (motion I-4). The lift still happens; it simply does not fly. ]]
	local ROW_LIFT = 1.05
	local liftEnv = surfaceEnv.forSpec(core, spec.env)
	local tenFootRows = Compose.formula(function(use)
		if liftEnv == nil then
			return false
		end
		local p = use(presentation)
		return (p == "inline" or p == "radio") and use(liftEnv:get("distanceProfile")) == "ten-foot"
	end)
	local focusedLeaf = Compose.cell(nil :: any)

	--[[ one row's lift, built the shape `button.luau` proved: a TARGET memo over
		the two facts, a settled signal the prop reads, and a spring created lazily
		the first time the target moves — so a row that is never focused costs a
		memo and nothing else. The painted value is nil at rest rather than 1,
		because a resting `scale = 1` is still an authored presentation transform
		and would put one on every row of every row list at every distance. ]]
	local function liftScaleFor(optionId: string): any
		local target = Compose.formula(function(use)
			return if use(tenFootRows) and use(focusedLeaf) == optionId then ROW_LIFT else 1
		end)
		local moving = if Facet.runtime.host.frames
			then Facet.runtime.spring(function(use)
				return use(target)
			end, { period = 0.28, damping = 1 })
			else target
		return function(use)
			local reduced = liftEnv ~= nil and use(liftEnv:get("motionPolicy")) == "reduced"
			local value = math.clamp(if reduced then use(target) else use(moving), 1, ROW_LIFT)
			return if value <= 1.0001 then nil else value
		end
	end

	-- A row option is the shared recipe's props plus this control's own corners
	-- and scale, emitted once so every bound prop keeps its binding.
	local rows: { any } = {}
	local byId: { [string]: any } = {}
	local segments: { any } = {}
	if requested == "segmented" and lint.hasDescription then
		error(
			`Facet UI.Picker('{id}'): a segmented picker's options cannot carry \`description\`. `
				.. "A segment is a label and nothing else (the reference platform draws the same); "
				.. 'a described option is a row — use `style = "inline"`, `"radioGroup"` or `"menu"`, '
				.. "or leave `style` automatic and the ladder picks a row form for you.",
			0
		)
	end
	for i, option in spec.options do
		local optionId = option.id or "Opt" .. i
		byId[optionId] = option.value
		table.insert(segments, { value = option.value, id = optionId })
		local badged = option.badge ~= nil
		--[[ THIS SEGMENT'S SHAPE, in one memo over the two facts that can move it.
			Both answers are built here, once, so the memo picks between two stable
			tables rather than allocating a corner set per re-solve. A strip that is
			not a track (a tab bar, or a strip with no indicator) takes the plain
			row shape, which is the same radius without the end rule. ]]
		local cornerX = stripCorners(UI, i, segmentCount, "x", outerCorner)
		local cornerY = stripCorners(UI, i, segmentCount, "y", outerCorner)
		cornersX[i], cornersY[i], cornersRow[i] = cornerX, cornerY, rowCorners
		local optionCorners: any = rowCorners
		if tracked then
			optionCorners = Compose.formula(function(use)
				if use(presentation) ~= "segmented" then
					return rowCorners
				end
				return if axisNow(use) == "y" then cornerY else cornerX
			end)
		end
		-- the lift is a ROW treatment, so a declared segmented strip never carries
		-- the machinery at all
		local liftScale = if requested ~= "segmented" then liftScaleFor(optionId) else nil
		local buttonProps: any = {
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
			enabled = Compose.formula(function(use)
				return controlContract.enabledIn(use, spec.enabled) and controlContract.enabledIn(use, option.enabled)
			end),
			textSize = spec.textSize,
			surface = if slides then "plain" else nil,
			selected = if slides
				then nil
				else Compose.formula(function(use)
					return selectionModel.read(selected, use) == option.value
				end),
			-- THE PLATE'S OWN CONTENT COLOUR, on whichever option the chip is under
			-- right now (see `platedRole` above). Reactive, and it names BOTH ends:
			-- a bound role that resolved to nil on the way back would drop the prop
			-- instead of writing the resting value, which is the one-way latch
			-- `Text.role`'s own `"content"` spelling exists to prevent — so the
			-- option the chip LEAVES is written "default", the role nothing tags.
			role = if platedRole == nil
				then nil
				else Compose.formula(function(use)
					return if selectionModel.read(selected, use) == option.value then platedRole else "default"
				end),
			-- inside a badge wrapper the Button FILLS the cell, so the cell's own
			-- width (the reactive one) is the single place the segment's size is
			-- decided and the two can never disagree
			width = if badged then SEGMENT_FILL else segmentWidth,
			height = if badged then OVERLAY_FILL else segmentHeight,
			padding = rungPadding,
			-- the focus ring follows the node's corners, so a segment wears the
			-- same shape as the bar sliding under it: one silhouette, one height.
			-- It is authored on EVERY form, not only the sliding one, because a row
			-- list's chosen row is a theme-painted plate on this same node — an
			-- authored corner is what makes chosen and unchosen one outline.
			corners = optionCorners,
			scale = liftScale,
			-- a segment's label has a full-value path (the large-text plate) the
			-- way any one-line label does: a strip that truncates at the largest
			-- preference under a roomy package is disclosed, never lost (the gap
			-- tests/lib/large_text_fixtures.luau recorded as closed on 2026-09-11,
			-- an option label with no route to the whole string). Not for a tab strip
			-- (`track = false`): a tab bar runs its own compact ladder, and the
			-- plate's reservation is height a fixed bar does not have.
			disclose = if slides and (spec :: any).track ~= false then true else nil,
		}
		if requested == "radio" or option.description ~= nil then
			buttonProps = menuRecipe.rowProps(UI, {
				id = optionId,
				label = option.label,
				textSize = spec.textSize,
				description = option.description,
				icon = option.icon,
				indicator = if requested == "radio" then "radio" else nil,
				indicatorEdge = spec.indicatorPosition,
				height = rungHeight and vocabulary.metricPath(readValue(spec.controlSize), "height"),
				markHidden = Compose.formula(function(use)
					return selectionModel.read(selected, use) ~= option.value
				end),
				selected = Compose.formula(function(use)
					return selectionModel.read(selected, use) == option.value
				end),
				enabled = Compose.formula(function(use)
					return controlContract.enabledIn(use, spec.enabled)
						and controlContract.enabledIn(use, option.enabled)
				end),
			})
			buttonProps.corners = optionCorners
			buttonProps.scale = liftScale
		end
		if not badged then
			table.insert(rows, UI.Button(buttonProps))
		else
			-- The shared row recipe measures label and badge in separate lanes.
			-- Overlaying a count on a short tab obscures its label, especially
			-- with distant metrics and an image-backed theme badge.
			local row = menuRecipe.rowProps(UI, {
				id = optionId,
				label = option.label,
				labelTint = if platedRole == nil
					then nil
					else Compose.formula(function(use)
						return {
							role = if selectionModel.read(selected, use) == option.value then "onAccent" else "content",
							blend = 1,
						}
					end),
				textSize = spec.textSize,
				icon = option.icon,
				iconOnly = iconOnly,
				badge = option.badge,
				wrap = true,
				description = option.description,
				indicator = if requested == "radio" then "radio" else nil,
				selected = Compose.formula(function(use)
					return selectionModel.read(selected, use) == option.value
				end),
				markHidden = Compose.formula(function(use)
					return selectionModel.read(selected, use) ~= option.value
				end),
			})
			local props = table.clone(buttonProps)
			props.id = optionId
			props.compactLabel = nil
			props.height = segmentHeight
			props.children = row.children
			local button = UI.Button(props)
			table.insert(
				rows,
				UI.ZStack({
					id = optionId .. "Cell",
					width = segmentWidth,
					height = segmentHeight,
					children = { button },
				})
			)
		end
		--[[ THE SEAM BETWEEN THIS SEGMENT AND THE NEXT (item 2). A hairline, not a
			gap: the two segments touch and one rule tells them apart, which is what
			makes the strip read as one control rather than a row of chips.

			HIDDEN BESIDE THE SELECTION, and that is not decoration. The indicator's
			layer is declared FIRST inside its ZStack so the fill paints BEHIND the
			strip (it must never take a tap meant for a segment) — so a seam adjacent
			to the chip draws a hairline down the chip's own edge. `hidden` keeps the
			layout box, so neither neighbour moves when the selection arrives.

			MOUNTED IN BOTH FORMS, never `When`-gated: a `When` inside the strip
			would make the tree structural and put the indicator's own segment-id
			check to sleep for every picker. The seam's main-axis size carries the
			row form's spacing instead (see SEAM_HAIRLINE). ]]
		if tracked and i < segmentCount then
			local nextValue = spec.options[i + 1].value
			local seamMain = Compose.formula(function(use)
				return if use(presentation) == "segmented" then SEAM_HAIRLINE else SEAM_ROW_GAP
			end)
			local vertical = Compose.formula(function(use)
				return use(axis) == "y"
			end)
			table.insert(
				rows,
				UI.Divider({
					id = `Sep{i}`,
					width = Compose.formula(function(use)
						return if use(vertical) then SEAM_CROSS else use(seamMain)
					end),
					height = Compose.formula(function(use)
						return if use(vertical) then use(seamMain) else SEAM_CROSS
					end),
					margin = Compose.formula(function(use)
						return if use(vertical) then SEAM_MARGIN_Y else SEAM_MARGIN_X
					end),
					hidden = Compose.formula(function(use)
						if use(presentation) ~= "segmented" then
							return true
						end
						local value = selectionModel.read(selected, use)
						return value == option.value or value == nextValue
					end),
				})
			)
		end
	end

	local group = UI.AdaptiveStack({
		id = "Options",
		axis = axis,
		-- a TRACKED strip spends no gap: the seam between each pair carries the
		-- spacing in both forms (see SEAM_HAIRLINE), so the segments touch while the
		-- strip is a track and the rows keep their `xs` step when it is not
		gap = if tracked then 0 else "xs",
		--[[ EVERY SEGMENT THE SAME SIZE, BY CONSTRUCTION rather than by luck
			(found by `tests/picker_sweep.spec.luau` on 2026-09-12, the
			fantasy-ornate / Largest / phone-portrait cell). The sweep has always
			required "every segment the same height"; it held only while the
			segments' labels happened to agree about whether they truncated. They
			are different words, so they do not have to: the longer one reserved its
			disclosure plate and the shorter one did not, and the strip solved 108px
			beside 66px. Cross-axis `stretch` makes the answer the STACK's, which is
			what a segmented control is — one track of equal cells — and it also
			gives the hairline seams their full run. ]]
		align = if tracked then "stretch" else nil,
		width = groupWidth,
		padding = if slides and (spec :: any).track ~= false then trackPaddingFor(core, spec, presentation) else nil,
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
			--[[ THE FILL WEARS THE SEGMENT'S OWN SHAPE (item 2, 2026-09-12). Without
				this the bar keeps one permanent silhouette while the segments have
				three, so a pill in a square middle segment leaves four slivers of
				track showing at its corners. The seam indexes this array by the
				SELECTED segment, which is the one fact it already holds. ]]
			--[[ ...REVISED 2026-09-12 (user ruling): the fill is the reference
				platform's INSET ROUNDED RECT, `radii.selection` on all four corners
				(`selection_indicator.DEFAULT_CORNER`), floating inside a track whose
				own ends keep `radii.control`. The per-segment silhouettes above are
				still the SEGMENTS' (`optionCorners`); the bar no longer borrows them. ]]
			segmentCorners = nil,
			--[[ THE CONTAINER THE FILL HAS TO MATCH (owner report 2026-09-12,
				controller ruling). A tracked strip's container is the `Track` plate
				below and its corner is `SEGMENT_RADIUS`; an untracked one's is the
				band its caller drew, which is the only thing `stripCorner` is for.
				`selection_indicator.fillCornerFor` carries the three clauses. ]]
			trackCorner = if (spec :: any).track == false
				then (spec :: any).stripCorner
				elseif spec.corners == "pill" then "pill"
				else SEGMENT_RADIUS,
			-- a square strip's fill is square too
			corner = if spec.corners == "square" and (spec :: any).track ~= false then 0 else nil,
			--[[ THE TRACK (visual review 2026-09-11). A segmented control is ONE
				plated track holding equal segments with the selected one raised; the
				bar alone left every unselected segment as bare text floating beside
				one pill. The plate is the `control` surface — the slot every shipped
				package skins (an ornate frame, a nine-slice, a gel) — drawn BENEATH
				the sliding bar, and only while the strip IS a segmented pill: the row
				list and the radio group are rows on the page, not a track.

				ITS CORNER IS THE STRIP'S OUTER CORNER (item 2): the same
				`radii.control` the two end segments round with, so the track and the
				ends are one outline rather than a capsule holding two squares. ]]
			plate = if (spec :: any).track == false
				then nil
				else UI.Box({
					id = "Track",
					-- `appearance`: filled is the plate, stroke an outline, utility none
					surface = function(use)
						return if readValue(spec.appearance, use) == "stroke" then "plain" else "control"
					end,
					stroke = function(use)
						return if readValue(spec.appearance, use) == "stroke" then trackOutline else nil
					end,
					corners = UI.cornersData(outerCorner),
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					hidden = Compose.formula(function(use)
						return use(presentation) ~= "segmented" or readValue(spec.appearance, use) == "utility"
					end),
				}),
		})
		owner.own(function()
			indicatorApi.dispose()
		end) -- the seam's whole lifetime is this control's
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

	--[[ WHICH OPTION THE RING IS ON, and it is deliberately scoped to THIS mount.
		The ten-foot lift keys on it, and a leaf match alone ("Opt2") would lift a
		row of the second picker on the same screen — so the focused path must sit
		under this control's own mounted root before its leaf counts. Degrades to
		"nothing focused" whenever either fact is missing, which is what a control
		with no presenter already gets. ]]
	local focusBound = false
	local function readFocused(path: any)
		if type(path) ~= "string" or mountedNode == nil then
			focusedLeaf:set(nil)
			return
		end
		if string.find(path, mountedNode.path .. "/", 1, true) ~= 1 then
			focusedLeaf:set(nil)
			return
		end
		focusedLeaf:set(string.match(path, "([^/]+)$"))
	end

	local built = contribution.attach(root, {
		syncGeometry = function(_, node)
			mountedNode = node
		end,
		-- an ENHANCEMENT seam, in both cases: with no focus graph nothing lifts,
		-- and with no clock the lift is an instant placement — the same supported
		-- degradation `selection_indicator` takes for its own springs
		bindFocusGraph = function(graph: any)
			if focusBound or graph == nil or graph.focused == nil then
				return
			end
			focusBound = true
			owner.watchStatic(graph.focused, readFocused)
			readFocused(graph.focused:peek())
		end,
		handleActivate = function(path: string): boolean
			local leaf = string.match(path, "([^/]+)$")
			if leaf ~= nil and byId[leaf] ~= nil then
				if onReselect and byId[leaf] == readValue(selected) and isEnabled() then
					onReselect()
				else
					choose(byId[leaf])
				end
				return true
			end
			return false
		end,
	})

	local api = {}
	-- a named rung can solve segments under the touch floor: reserve it once
	api.blueprint = if rungHeight ~= nil then vocabulary.reserveTarget(UI, core, id, built, groupWidth) else built
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
		local current = readValue(selected)
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
			presentation = presentation:peek(),
			-- WHERE THE ADAPTIVE FACT CAME FROM: "spec" (the author wired
			-- it), "core" (the surface's own environment answered, no wiring), or
			-- "none" (a declared presentation, which consults no ladder at all). A
			-- screen can be audited for adaptation it never had to author.
			sizeClassFrom = sizeClassFrom,
			axis = axis:peek(),
			-- THE FIELD THAT TELLS THE TWO "y" SHAPES APART. A vertical pill and an
			-- inline row list both report `axis = "y"`; only this says which one is
			-- on screen, so a report of "the picker went full width" is answerable.
			verticalPill = verticalPill:peek(),
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
		owner.dispose()
	end

	return api
end

--[[ THE CARDS STYLE: each option a selectable card built on the shared
	`menu_recipe.cardRow` (its selected surface and paired lettering, its corners
	from `cardCorners`) with a hairline edge at rest. A column by default; a row
	(`axis = "x"`) WRAPS onto more lines rather than running off its offer, and
	each card hugs no wider than its offer so long copy wraps. Selection is the
	shared `selectionModel.choose`; with `required = false` choosing the selected
	card again clears it. ]]
local CARD_EDGE = table.freeze({ color = "hairline", thickness = "hairline", transparency = 0 })
local function buildCardsOwned(Facet: any, core: any, spec: any, owner: any)
	local UI = Facet.UI
	local id = spec.id or "Picker"
	local mountedNode
	assert(selectionModel.isWritable(spec.selected), "UI.Picker: selected must be a writable Compose cell")
	local function key(option)
		return option.id or tostring(option.value)
	end
	local options = Compose.formula(function(use)
		local list = readValue(spec.options, use)
		validateArray(list)
		for _, option in list do
			validateOption(option, use)
		end
		return list
	end)
	options:peek()
	local axis = readValue(spec.axis) or "y"
	local function choose(option: any)
		if
			owner.isDisposed()
			or controlContract.isDisabled(mountedNode)
			or not controlContract.enabledNow(spec.enabled)
		then
			return
		end
		local current = readValue(spec.selected)
		local proposed = if current == option.value and spec.required == false then nil else option.value
		local accepted, nextValue =
			selectionModel.choose(options:peek(), current, proposed, spec.required, spec.onChanging)
		if accepted and not owner.isDisposed() then
			core.reactor:batch(function()
				spec.selected:set(nextValue)
				if spec.onChange then
					spec.onChange(nextValue)
				end
			end)
		end
	end
	local rows = UI.ForEach({
		id = "Cards",
		items = options,
		key = key,
		row = function(initial, _, current)
			local function prop(name, fallback)
				return function(use)
					local value = readValue(use(current)[name], use)
					return if value == nil then fallback else value
				end
			end
			local card = menuRecipe.cardRow(UI, {
				id = "Card-" .. key(initial),
				label = prop("label"),
				description = prop("description", ""),
				icon = if initial.icon ~= nil then prop("icon") else nil,
				badge = if initial.badge ~= nil then prop("badge", "") else nil,
				value = if initial.meta ~= nil then prop("meta", "") else nil,
				platedSelection = true,
				textSize = spec.textSize,
				width = if axis == "x" then UI.hug() else nil,
				-- a hugging card's words hug too (fill inside hug would be nothing)
				wrap = axis == "x",
				selected = function(use)
					return selectionModel.read(spec.selected, use) == use(current).value
				end,
				enabled = function(use)
					return controlContract.enabledIn(use, spec.enabled)
						and controlContract.enabledIn(use, use(current).enabled)
				end,
			}, "only")
			return contribution.attach(UI.stroke(card, CARD_EDGE), {
				handleActivate = function()
					choose(readValue(current))
					return true
				end,
			})
		end,
	})
	local group = if axis == "x"
		then UI.HStack({ id = "Options", wrap = true, gap = "s", width = BAND_WIDTH, children = { rows } })
		else UI.VStack({ id = "Options", gap = "s", width = BAND_WIDTH, children = { rows } })
	local children = { group }
	if spec.label then
		table.insert(children, 1, UI.Text({ id = "Label", text = spec.label, textSize = "label", width = UI.fill() }))
	end
	local blueprint = contribution.attach(UI.VStack({ id = id, width = BAND_WIDTH, gap = "xs", children = children }), {
		syncGeometry = function(_, node)
			mountedNode = node
		end,
	})
	local presentation = Compose.formula(function()
		return "cards"
	end)
	return {
		blueprint = blueprint,
		presentation = presentation,
		dump = function()
			return {
				schema = "facet-picker-dump/1",
				id = id,
				selected = readValue(spec.selected),
				presentation = "cards",
				style = "cards",
				requestedStyle = "cards",
				axis = axis,
				optionCount = #options:peek(),
			}
		end,
		dispose = function()
			owner.dispose()
		end,
	}
end

local function buildStrip(Facet, core, spec, requested, onReselect)
	return ownedBuild(core, function(owner)
		return buildStripOwned(Facet, core, spec, requested, onReselect, owner)
	end)
end

-- ===== THE STYLE ROUTER (2026-09-11) =======================================
-- `build` validates what every style shares, normalizes the deprecated
-- `presentation` spelling onto `style`, and hands the spec to the builder the
-- style names: the popup engine for `menu` / `navigationLink`, the strip
-- builders above for the rest, and — for `automatic` — a two-branch `UI.When`
-- that swaps the FAMILY when the facts move (a distance or input-class flip is
-- a structural change: a pop-up button and a row list share no node), while a
-- flip WITHIN the strip family stays the re-solve it always was (A-AL2).

local MENU_STYLES: { [string]: boolean } = { menu = true, navigationLink = true }

-- the public style a spec asked for, with the deprecated alias folded in
local function requestedStyle(spec: Spec, id: string): string
	local style = spec.style
	if spec.presentation ~= nil then
		if style ~= nil then
			error(
				`Facet UI.Picker('{id}'): \`presentation\` is the deprecated spelling of \`style\`; pass one, not both.`,
				0
			)
		end
		local legacy = spec.presentation
		if not PRESENTATIONS[legacy] then
			error(
				`Facet UI.Picker('{id}'): unknown presentation '{tostring(legacy)}'. \`presentation\` is deprecated — `
					.. `write \`style\` ({STYLE_LIST}).`,
				0
			)
		end
		style = if legacy == "radio" then "radioGroup" else legacy
	end
	style = style or "automatic"
	if not STYLES[style] then
		error(
			`Facet UI.Picker('{id}'): unknown style '{tostring(style)}'. One of {STYLE_LIST}. `
				.. "There is no wheel or palette: a short list is `segmented`, a long one is `menu` or `navigationLink`.",
			0
		)
	end
	return style
end

-- the spec the popup engine reads: the picker's own keys, the style, and nothing
-- the strip builders own (`indicator`, `axis`, `iconOnly` mean nothing to a menu)
local function menuSpec(spec: Spec, style: string, id: string): any
	return {
		id = id,
		style = style,
		options = spec.options,
		selected = spec.selected,
		label = fieldChrome.labelText(spec.label, spec.requiredMark),
		valueAlignment = spec.valueAlignment,
		sizing = readValue(spec.sizing),
		textSize = spec.textSize,
		query = spec.query,
		placeholder = spec.placeholder,
		required = spec.required,
		onChanging = spec.onChanging,
		onChange = spec.onChange,
		enabled = spec.enabled,
		env = spec.env,
		sizeClass = spec.sizeClass,
		errorText = spec.errorText,
		controlSize = spec.controlSize,
		corners = spec.corners,
		maxHeight = spec.maxHeight,
		appearance = vocabulary.derive(spec.appearance, function(word)
			return if type(word) == "string" then TO_MENU[word] else nil
		end),
	}
end

-- the spec a strip builder reads: everything but the popup-only keys and the
-- style spellings (the builder takes the strip name as an argument)
local function stripSpec(spec: Spec, id: string): any
	local out = table.clone(spec :: any)
	out.id = id
	out.style, out.presentation, out.query, out.placeholder = nil, nil, nil, nil
	out.label = fieldChrome.labelText(spec.label, spec.requiredMark)
	out.appearance = vocabulary.derive(spec.appearance, function(word)
		return if type(word) == "string" then TO_STRIP[word] else nil
	end)
	return out
end

local function buildMenu(Facet: any, core: any, spec: Spec, style: string, id: string): any
	local inner = pickerMenu.build(Facet, core, menuSpec(spec, style, id))
	local presentation = Compose.formula(function()
		return style
	end)
	local api: any = {
		blueprint = inner.blueprint,
		api = inner.api,
		presentation = presentation,
		dispose = function()
			inner.dispose()
			presentation:dispose()
		end,
	}
	function api.dump()
		local out = inner.dump()
		out.schema = "facet-picker-dump/1"
		out.requestedStyle = style
		out.style = style
		-- a menu wears no sliding indicator; the field stays so a reader written
		-- against a strip's dump finds an answer rather than a hole
		out.indicator = "none"
		return out
	end
	return api
end

local function buildStripFamily(Facet: any, core: any, spec: Spec, style: string, id: string, onReselect): any
	local strip = if style == "automatic" then "automatic" else STRIP_NAME[style]
	local live = selectionModel.isSource(spec.options)
	local inner = if live
		then buildLive(Facet, core, stripSpec(spec, id), strip, onReselect)
		else buildStrip(Facet, core, stripSpec(spec, id), strip, onReselect)
	local presentation = Compose.formula(function(use)
		return PUBLIC_NAME[use(inner.presentation)] or use(inner.presentation)
	end)
	local api: any = {
		blueprint = inner.blueprint,
		segments = inner.segments,
		presentation = presentation,
		dispose = function()
			inner.dispose()
			presentation:dispose()
		end,
	}
	function api.dump()
		local out = inner.dump()
		out.requestedStyle = style
		out.style = PUBLIC_NAME[out.presentation] or out.presentation
		return out
	end
	return api
end

local function buildAutomaticOwned(Facet: any, core: any, spec: Spec, id: string, owner: any): any
	local UI = Facet.UI
	local env = surfaceEnv.resolve(
		"UI.Picker",
		id,
		core,
		spec.env,
		"an automatic style adapts to the size class, the viewing distance and the primary interaction class"
	)
	local sizeClassSource: any = spec.sizeClass or env:get("sizeClass")
	local searchable = spec.query ~= nil

	local offerWidth = Compose.cell(nil :: number?)
	local function bandEstimate(use: any, list: { any }): number
		local metrics = use(env:get("themeMetrics"))
		local snap = if type(metrics) == "table" and type(metrics.controls) == "table"
			then metrics
			else themeSnapshot.neutral()
		local base = themeSnapshot.resolveSize(snap, spec.textSize or "control") or 16
		local scale = themeSnapshot.typographyScale(use(env:get("displaySize")), use(env:get("preferredTextSize")))
		local textPx = base * scale + themeSnapshot.textOffset(use(env:get("preferredTextOffset")))
		local sizes = (snap :: any).controlSizes
		local padX = if type(sizes) == "table"
				and type(sizes.regular) == "table"
				and type(sizes.regular.paddingX) == "number"
			then sizes.regular.paddingX
			else 12
		local gap = themeSnapshot.resolveNumber(snap, "space.xs") or 4
		-- the live adapter calibrates the theme's font (src/client/text_calibration);
		-- a calibrated family tightens the estimate, an unknown one keeps the
		-- conservative fraction every uncalibrated measurement uses
		local role = themeSnapshot.roleOf(snap, spec.textSize or "control")
		local family = if type(role) == "table" and type(role.font) == "table" then role.font.family else nil
		local fraction = if type(family) == "string"
			then textMetrics.calibrationTable()[family] or textMetrics.AVG_GLYPH_FRACTION
			else textMetrics.AVG_GLYPH_FRACTION
		local total = 0
		for _, option in list do
			local label = tostring(readValue(option.label, use))
			total += #label * textPx * fraction + 2 * padX
		end
		return total + gap * math.max(0, #list - 1)
	end
	local style = Compose.formula(function(use)
		local list = readValue(spec.options, use)
		local longest = 0
		local described = false
		for _, option in list do
			longest = math.max(longest, #tostring(readValue(option.label, use)))
			if readValue(option.description, use) ~= nil then
				described = true
			end
		end
		local classes = use(env:get("interactionClasses"))
		local offer = use(offerWidth)
		local vertical = readValue(spec.axis, use) == "y"
		if readValue(spec.sizing, use) == "hug" or type(offer) ~= "number" or offer <= 0 then
			local vp = use(env:get("viewportRect"))
			offer = if type(vp) == "table" and type(vp.w) == "number" then vp.w - 32 else 1280
		end
		return picker.resolveStyle({
			optionCount = #list,
			longestLabel = longest,
			sizeClass = readValue(sizeClassSource, use),
			distanceProfile = use(env:get("distanceProfile")),
			primaryInput = if type(classes) == "table" then classes.primary else "pointer",
			searchable = searchable,
			hasDescription = described,
			-- a vertical rail stacks its segments, so the band's LENGTH is not a
			-- width and the row has nothing to refuse it on
			fits = vertical or bandEstimate(use, list) <= offer,
		})
	end)
	local rootWidth = Compose.formula(function(use)
		local current = use(style)
		if MENU_STYLES[current] then
			return BAND_WIDTH
		end
		if current == "segmented" and readValue(spec.axis, use) == "y" then
			return RAIL_WIDTH
		end
		return if readValue(spec.sizing, use) == "hug" then NATURAL_WIDTH else BAND_WIDTH
	end)
	local live: any = nil
	local nativeContent = Compose.keyed({
		from = function(use)
			local current = use(style)
			return { { key = if MENU_STYLES[current] then current else "strip", style = current } }
		end,
		key = function(item)
			return item.key
		end,
		render = function(item)
			local selected = item:peek()
			local inner
			if selected.key == "strip" then
				local handed = table.clone(spec)
				handed._presentationSource = style
				inner = buildStripFamily(Facet, core, handed, "automatic", "StripBody")
			else
				inner = buildMenu(Facet, core, spec, selected.style, "MenuBody")
			end
			live = inner
			Compose.cleanup(function()
				if live == inner then
					live = nil
				end
				inner.dispose()
			end)
			return inner.blueprint
		end,
	})
	local blueprint = contribution.attach(
		UI.VStack({
			id = id,
			width = rootWidth,
			children = { nativeContent },
		}),
		{
			syncGeometry = function(rectOf, node)
				if node == nil then
					return
				end
				local rect = rectOf(node.path)
				if
					type(rect) == "table"
					and type(rect.w) == "number"
					and rect.w > 0
					and offerWidth:peek() ~= rect.w
				then
					offerWidth:set(rect.w)
				end
			end,
		}
	)
	local api: any = {
		blueprint = blueprint,
		presentation = style,
		-- the popup verbs, live only while the menu family is on screen; a
		-- strip has nothing to open, so they are a no-op there rather than an error
		api = {
			open = function()
				if live ~= nil and live.api ~= nil then
					live.api.open()
				end
			end,
			close = function()
				if live ~= nil and live.api ~= nil then
					live.api.close()
				end
			end,
			select = function(value: any)
				if live ~= nil and live.api ~= nil then
					live.api.select(value)
				end
			end,
		},
		dispose = function()
			owner.dispose()
		end,
	}
	function api.dump()
		local out = if live ~= nil then live.dump() else {}
		out.schema = "facet-picker-dump/1"
		out.id = id
		out.requestedStyle = "automatic"
		out.style = style:peek()
		-- before a branch has mounted, the resolved style IS the presentation
		if out.presentation == nil then
			out.presentation = out.style
		end
		if out.indicator == nil then
			out.indicator = "none"
		end
		out.sizeClassFrom = if spec.sizeClass ~= nil then "spec" else "core"
		out.selected = readValue(spec.selected)
		return out
	end
	return api
end
local function buildAutomatic(Facet, core, spec, id)
	return ownedBuild(core, function(owner)
		return buildAutomaticOwned(Facet, core, spec, id, owner)
	end)
end

-- Internal tab-host hook: accepting the current destination completes its chooser without a change event.
function picker.build(Facet: any, core: any, spec: Spec, onReselect: (() -> ())?)
	specGuard.assertKnownKeys("UI.Picker", spec, PICKER_KEYS, "spec")
	local id = spec.id or "Picker"
	assert(spec.required == nil or type(spec.required) == "boolean", "Picker: required must be boolean")
	for _, name in { "onChanging", "onChange" } do
		assert(spec[name] == nil or type(spec[name]) == "function", `Picker: {name} must be a function`)
	end
	local enabled = readValue(spec.enabled)
	assert(enabled == nil or type(enabled) == "boolean", "Picker: enabled must be boolean or readable boolean")
	assert(spec.axis == nil or AXES[readValue(spec.axis)], "Picker: axis must be x | y")
	assert(spec.sizing == nil or SIZINGS[readValue(spec.sizing)], "Picker: sizing must be fill | hug")
	local valueAlignment = readValue(spec.valueAlignment)
	assert(
		valueAlignment == nil or valueAlignment == "start" or valueAlignment == "end",
		"Picker: valueAlignment must be start | end"
	)
	assert(spec.iconOnly == nil or type(spec.iconOnly) == "boolean", "Picker: iconOnly must be boolean")
	--[[ `stripCorner` IS REFUSED RATHER THAN IGNORED, both ways (review round 2).
		It was the one key in this spec with no assert, and it is spent by exactly
		one branch, so a wrong value or a wrong combination resolved to nothing
		three layers down with no word to the author.

		THE VALUE is a CONTAINER NAME, the vocabulary `selection:<container>` takes
		(`src/tokens/styling.luau`): a radius token the base style publishes, which
		is what the fill resolver can look up. A colon-namespaced radius is
		deliberately not one — the token's own grammar excludes it.

		THE COMBINATION: a TRACKED strip draws its own plate, at `SEGMENT_RADIUS`,
		so the container is already known and a caller naming a different one is
		stating a contradiction rather than adding information. Only `track = false`
		— a strip inside a band its caller drew — has a container to declare. The
		message says which of the two to drop, because either could be the mistake. ]]
	if spec.stripCorner ~= nil then
		--[[ A READABLE THAT CURRENTLY READS `nil` IS LEGAL and means "no container
			right now": `TabView` hands one in whose value is the band's capsule in
			the band form and nothing in the rail form, because a rail row is not
			concentric with the rail. Only a value that is present and is not a
			container name is an authoring mistake. ]]
		local declared = readValue(spec.stripCorner)
		--[[ AGAINST THE RADII THE FILL WILL ACTUALLY RESOLVE THROUGH (task 7 item
			11). The vocabulary is derived from the BASE style, which is right for
			every caller under Facet Neutral and wrong for a package that authors a
			radius of its own: `radii.selection:chip` resolves perfectly well under
			one, and this check refused the name before it could get there. So the
			live metrics are read when a surface env is in hand — a package may ADD
			to the vocabulary, never narrow it — and when none is, the message says
			as much rather than pretending the base set is the whole world. ]]
		local liveRadii: any = nil
		do
			local themeEnv: any = surfaceEnv.forSpec(core, spec.env)
			if type(themeEnv) == "table" and type(themeEnv.get) == "function" then
				local metrics: any = themeEnv:get("themeMetrics")
				local snap: any = if Compose.isReadable(metrics) then metrics:peek() else nil
				liveRadii = if type(snap) == "table" and type(snap.radii) == "table" then snap.radii else nil
			end
		end
		if declared ~= nil and not styling.isSelectionContainer(declared, liveRadii) then
			local source = if liveRadii ~= nil
				then ""
				else " No theme is in hand at this call, so that vocabulary is the BASE style's: "
					.. "a radius a package adds of its own can be named from a themed surface."
			error(
				`Facet UI.Picker('{id}'): stripCorner must name a container radius `
					.. `({styling.selectionContainerList(liveRadii)}) — the vocabulary the selected fill resolves `
					.. `through \`radii.selection:<container>\`. Got '{tostring(declared)}'.{source}`,
				0
			)
		end
		if (spec :: any).track ~= false then
			error(
				`Facet UI.Picker('{id}'): stripCorner names the plate AROUND this strip, and a tracked `
					.. `strip draws its own plate. Either pass \`track = false\` (the band owns the plate) `
					.. `or drop \`stripCorner\` (this picker's own track is the container).`,
				0
			)
		end
	end
	assert(
		spec.query == nil or (selectionModel.isWritable(spec.query) and type(readValue(spec.query)) == "string"),
		"UI.Picker: query must be a writable Compose cell holding a string"
	)
	assert(spec.placeholder == nil or type(spec.placeholder) == "string", "Picker: placeholder must be a string")
	local style = requestedStyle(spec, id)
	assert(
		style ~= "radioGroup" or not spec.iconOnly,
		"Picker: the radioGroup style requires visible labels; iconOnly is incompatible"
	)
	local indicatorRequest = spec.indicator or "automatic"
	if not INDICATORS[indicatorRequest] then
		error(
			`Facet UI.Picker('{id}'): unknown indicator '{tostring(indicatorRequest)}'. `
				.. "One of automatic | none | underline | pill. "
				.. "The sliding indicator is a PROPERTY of this control, not a construct you build yourself.",
			0
		)
	end
	if type(spec.options) ~= "table" and not selectionModel.isSource(spec.options) then
		error(`Facet UI.Picker('{id}'): \`options\` must be a non-empty array of value/label pairs`, 0)
	end
	if not selectionModel.isSource(spec.options) then
		if #spec.options == 0 then
			error(`Facet UI.Picker('{id}'): \`options\` must be a non-empty array of value/label pairs`, 0)
		end
		validateArray(spec.options)
		lintStaticOptions(spec, id)
	end
	if spec.query ~= nil and style ~= "automatic" and style ~= "navigationLink" then
		error(`Facet UI.Picker('{id}'): \`query\` (a searchable list) belongs to the navigationLink style.`, 0)
	end
	-- the field furniture: notation, the message line, rung and silhouette words
	fieldChrome.assertSpec("UI.Picker", {
		requiredMark = spec.requiredMark,
		hint = spec.hint,
		errorText = spec.errorText,
		controlSize = spec.controlSize,
		corners = spec.corners,
	})
	if spec.indicatorPosition ~= nil then
		if spec.indicatorPosition ~= "leading" and spec.indicatorPosition ~= "trailing" then
			error(`Facet UI.Picker('{id}'): indicatorPosition must be leading | trailing`, 0)
		end
		if style ~= "radioGroup" then
			error(`Facet UI.Picker('{id}'): indicatorPosition places the radio mark; the {style} style has none.`, 0)
		end
	end
	local words = wordsFor(style)
	if spec.appearance ~= nil then
		if words == nil then
			error(
				`Facet UI.Picker('{id}'): \`appearance\` belongs to the menu trigger and the segmented strip; `
					.. `the {style} style draws rows and takes none.`,
				0
			)
		end
		-- the automatic family's current answer checks its own words at the write
		vocabulary.assertAppearance("UI.Picker", spec.appearance, words, specGuard.keySet(words))
		local checked = spec.appearance
		spec = table.clone(spec :: any)
		spec.appearance = vocabulary.derive(checked, function(word)
			vocabulary.assertAppearance("UI.Picker", word, words, specGuard.keySet(words))
			return word
		end)
	end
	if spec.maxHeight ~= nil and style ~= "automatic" and not MENU_STYLES[style] then
		error(`Facet UI.Picker('{id}'): \`maxHeight\` bounds the menu panel; the {style} style has none.`, 0)
	end
	local built
	if MENU_STYLES[style] then
		built = buildMenu(Facet, core, spec, style, id)
	elseif style == "cards" then
		built = ownedBuild(core, function(owner)
			return buildCardsOwned(Facet, core, stripSpec(spec, id), owner)
		end)
	elseif style ~= "automatic" then
		built = buildStripFamily(Facet, core, spec, style, id, onReselect)
	else
		built = buildAutomatic(Facet, core, spec, id)
	end
	-- one message line under whichever family is on screen
	if spec.hint ~= nil or spec.errorText ~= nil then
		local chrome = fieldChrome.new({
			UI = Facet.UI,
			control = "UI.Picker",
			spec = { hint = spec.hint, errorText = spec.errorText },
		})
		built.blueprint = chrome.wrap(built.blueprint, id)
	end
	return built
end

return picker
