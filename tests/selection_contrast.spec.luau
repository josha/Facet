--!strict
--[[ EVERY SHIPPED THEME, ASKED WHETHER ITS SELECTED TEXT CAN BE READ (user
	review, 2026-09-12: *"Glossy Touch: selected-row text paints black on the blue
	selection fill — illegible"*).

	WHAT THE DEFECT ACTUALLY WAS, because the palette was not wrong. Glossy Touch
	declares `extra.controlSelected = rgb(20, 81, 194)` — a saturated blue, and
	correctly so: `tests/theme_reference_packages.spec.luau` pins that declaration
	against the package's own `glossy_selection_selected` ART, and the art is a
	blue gel. The library already resolves a partner for it: `$OnSelected`
	(`sheet_model.selectedContentColor`) picks `$Content` wherever content still
	clears 4.5:1 and `$OnAccent` where it does not — white, here, at 7.03:1.

	The label never reached that token. A menu row inside a CARD goes
	`surface = "plain"`, which suppresses the `facet-selected` tag (an explicit
	`plain` paints nothing, states included), so the `Selected row` rule never
	fires; and a row with a check, an icon or a description draws its label into a
	CHILD `UI.Text`, which no `TextButton`-scoped colour rule in the sheet can
	reach even when it does. So the label kept the colour chosen to read on the
	page — `$Content` — and sat on the selection fill at 2.37:1.

	THE FLOOR IS THEREFORE ASKED OF THE PAINT, NOT ONLY OF THE PALETTE. Three
	gates, per theme of every shipped package:

	  1. text on `accent` — `onAccent`/`accent`, the theme contract's one gated
	     pair, restated here because the card's selection now spends it;
	  2. text on `controlSelected` as the SHEET MODEL resolves it — `$OnSelected`
	     against the selected surface, the pair the framework's own `Selected row`
	     rule paints;
	  3. the selected card row's label colour against the fill it sits on, READ
	     OFF THE ROW `menu_recipe.cardRow` actually builds. This is the one that
	     would have caught the report: a label whose paint is not chosen for its
	     fill fails it on every theme whose selected fill is not near-white.

	...and one CENSUS with pinned numbers (case 4): what an UNPAIRED label would
	read at on each theme's `controlSelected`. It is not a gate on the palettes —
	two themes are below the floor by construction and their declarations are
	correct — it is the measurement that says why gate 3 exists, and it fails if a
	third theme joins them, because that is a fact somebody must look at.

	The contrast formula is written out below rather than imported so this file
	states the standard it holds themes to. `tokens.contrastRatio` is the library's
	own implementation and the two are asserted equal on every pair measured here,
	which is what keeps "written out" from meaning "a second, drifting copy".
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local tokens = require("../src/tokens/tokens")
local sheet_model = require("../src/tokens/sheet_model")
local menuRecipe = require("../src/controls/menu_recipe")

local UI = Facet.UI

-- the eight shipped packages, the same list `tests/overflow_sweep.spec.luau`
-- sweeps, so a ninth package joins both or neither
local PACKAGE_MODULES: { { id: string, module: any } } = {
	{ id = "classic-desktop", module = require("../examples/themes/classic_desktop") },
	{ id = "compact-pointer", module = require("../examples/themes/compact_pointer") },
	{ id = "fantasy-ornate", module = require("../examples/themes/fantasy_ornate") },
	{ id = "fantasy-parchment", module = require("../examples/themes/fantasy_parchment") },
	{ id = "glossy-mobile", module = require("../examples/themes/glossy_mobile") },
	{ id = "glossy-touch", module = require("../examples/themes/glossy_touch") },
	{ id = "pixel-quest", module = require("../examples/themes/pixel_quest") },
	{ id = "scifi-hud", module = require("../examples/themes/scifi_hud") },
}

local FLOOR = 4.5

--[[ WCAG 2.x relative luminance and contrast ratio, written out.

	  channel c in 0..1:  c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4
	  L                =  0.2126 R + 0.7152 G + 0.0722 B
	  ratio            =  (Lmax + 0.05) / (Lmin + 0.05)

	1.0 is two identical colours and 21.0 is black against white. 4.5 is the floor
	for body text at ordinary sizes, which is what every label measured here is. ]]
local function channel(c: number): number
	if c <= 0.03928 then
		return c / 12.92
	end
	return ((c + 0.055) / 1.055) ^ 2.4
end

local function luminance(color: { r: number, g: number, b: number }): number
	return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b)
end

local function contrast(a: { r: number, g: number, b: number }, b: { r: number, g: number, b: number }): number
	local la, lb = luminance(a), luminance(b)
	local hi, lo = math.max(la, lb), math.min(la, lb)
	return (hi + 0.05) / (lo + 0.05)
end

local function round2(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

-- every theme of every package, built through the package gate each one ships
local THEMES: { { pkg: string, name: string, colors: any, extra: any } } = {}
for _, entry in PACKAGE_MODULES do
	local pkg, report = entry.module.build(Facet.themes)
	assert(
		pkg ~= nil,
		`{entry.id} failed its own package gate: {report and report.errors[1] and report.errors[1].message}`
	)
	for _, theme in pkg.style.themes do
		table.insert(THEMES, { pkg = entry.id, name = theme.name, colors = theme.colors, extra = theme.extra })
	end
end

--[[ THE PALETTE ROLE A PAINT CHANNEL NAMES, resolved to the theme's own colour.
	The card names roles (`menu_recipe.SELECTED_SURFACE`, `SELECTED_LABEL_ROLE`),
	never literals, so this is the whole mapping the measurement needs. A `plain`
	row paints nothing, so what is behind its label is the CARD — a `raised` panel,
	whose fill is `$SurfaceStrong`. ]]
local function roleColor(theme: any, role: string?): any
	if role == nil or role == "plain" then
		return theme.colors.surfaceStrong
	elseif role == "accent" then
		return theme.colors.accent
	elseif role == "onAccent" then
		return theme.colors.onAccent
	elseif role == "content" then
		return theme.colors.content
	elseif role == "controlSelected" then
		return sheet_model.selectedSurfaceOf(theme)
	elseif role == "raised" then
		return theme.colors.surfaceStrong
	end
	error(`selection_contrast: no palette colour for role '{tostring(role)}'`, 0)
end

local function readFact(value: any): any
	if type(value) == "table" and (value.kind == "signal" or value.kind == "memo") then
		return value:get()
	end
	return value
end

local function findById(bp: any, id: string): any
	if type(bp) ~= "table" then
		return nil
	end
	if bp.id == id then
		return bp
	end
	for _, child in bp.children or {} do
		local hit = findById(child, id)
		if hit ~= nil then
			return hit
		end
	end
	return nil
end

--[[ BUILD THE SELECTED CARD ROW THE MENU ACTUALLY PRESENTS, and report the two
	colours it paints: the fill (the row's own resolved `surface`) and the label.

	The label is read in the order the engine resolves it: an authored `tint` wins
	outright (it CLAIMS `TextColor3`); with none, a leaf row's label is the
	`TextButton` the sheet paints from its surface, and an `accent` surface's rule
	is `$OnAccent`; with neither, it is the theme's `$Content`. Reading the built
	blueprint rather than restating the constants is what makes this a measurement
	of the shipped row instead of a restatement of this file. ]]
local function cardRowPaint(selected: boolean): { fill: string?, label: string }
	local core = Facet.newCore()
	local scope = core:scope("selection-contrast")
	local signal = scope:own(core:signal(selected))
	local row = menuRecipe.cardRow(UI, core, scope, {
		id = "Item:probe",
		label = "Probe",
		-- a CHECK row: the shape a menu marks a current value with, and the shape
		-- whose label is a child `UI.Text` rather than the button's own text
		indicator = "check",
		selected = signal,
		markHidden = scope:own(core:memo(function(use)
			return not use(signal)
		end)),
		platedSelection = true,
		core = core,
		scope = scope,
	}, "only")
	local button = findById(row, "Item:probe")
	local label = findById(row, "Label")
	assert(button ~= nil and label ~= nil, "selection_contrast: the card row lost its button or its label")
	local surface = readFact(button.props.surface)
	local tint = readFact(label.props.tint)
	local labelRole: string
	if type(tint) == "table" and tint.role ~= nil then
		labelRole = tint.role
	elseif surface == "accent" then
		labelRole = "onAccent" -- the sheet's `Primary button label` rule
	else
		labelRole = "content" -- the class default, `Text default`
	end
	scope:dispose()
	return { fill = surface, label = labelRole }
end

describe("selection contrast: every shipped theme, every selected label", function()
	it("the written formula agrees with the library's own, on every pair measured here", function()
		-- the copy in this file exists to STATE the standard; it may not become a
		-- second, drifting implementation of it
		for _, theme in THEMES do
			local pairs_: { { any } } = {
				{ theme.colors.onAccent, theme.colors.accent },
				{ theme.colors.content, sheet_model.selectedSurfaceOf(theme) },
				{ theme.colors.content, theme.colors.surface },
			}
			for _, pair in pairs_ do
				expect(round2(contrast(pair[1], pair[2]))).toBe(round2(tokens.contrastRatio(pair[1], pair[2])))
			end
		end
		expect(#THEMES).toBe(11)
	end)

	it("1. text on `accent` clears 4.5:1 — the pair the card's selection spends", function()
		local worst, worstAt = math.huge, ""
		for _, theme in THEMES do
			local ratio = contrast(theme.colors.onAccent, theme.colors.accent)
			if ratio < worst then
				worst, worstAt = ratio, `{theme.pkg}/{theme.name}`
			end
			if ratio < FLOOR then
				error(
					`{theme.pkg}/{theme.name}: onAccent on accent is {round2(ratio)}:1, below {FLOOR}. `
						.. "`accent`/`onAccent` is the one pair a theme guarantees, and the selected menu "
						.. "row now spends it (menu_recipe.SELECTED_SURFACE / SELECTED_LABEL_ROLE).",
					0
				)
			end
		end
		-- the tightest theme in the corpus, pinned so a palette edit that eats the
		-- margin shows up as a number rather than as a still-green suite
		expect(`{worstAt}@{round2(worst)}`).toBe("glossy-mobile/Daylight@5.96")
	end)

	it("2. text on `controlSelected` clears 4.5:1 — the pair the sheet's `Selected row` rule paints", function()
		local picked: { string } = {}
		for _, theme in THEMES do
			local fill = sheet_model.selectedSurfaceOf(theme)
			local on = sheet_model.selectedContentColor(theme)
			local ratio = contrast(on, fill)
			if ratio < FLOOR then
				error(
					`{theme.pkg}/{theme.name}: $OnSelected on $ControlSelected is {round2(ratio)}:1, below `
						.. `{FLOOR}. A theme whose selected surface can carry NEITHER $Content nor $OnAccent `
						.. "has published a state nobody can read.",
					0
				)
			end
			local isContent = on.r == theme.colors.content.r and on.g == theme.colors.content.g
			table.insert(picked, `{theme.pkg}/{theme.name}={if isContent then "content" else "onAccent"}`)
		end
		table.sort(picked)
		-- WHICH partner each theme resolves, pinned: a flip here is a visible
		-- change to every selected row in that package
		expect(table.concat(picked, " ")).toBe(
			"classic-desktop/Day=content classic-desktop/Night=content compact-pointer/Aqua=content "
				.. "fantasy-ornate/Crypt=content fantasy-ornate/Grand Hall=content "
				.. "fantasy-parchment/Candlelight=content fantasy-parchment/Daylight=content "
				.. "glossy-mobile/Daylight=content glossy-touch/Sky=onAccent pixel-quest/Quest=onAccent "
				.. "scifi-hud/Nightwatch=content"
		)
	end)

	it("3. the SELECTED CARD ROW's own label clears 4.5:1 against the fill it sits on", function()
		local paint = cardRowPaint(true)
		-- the row is measured, not described: these two come off the blueprint
		expect(paint.fill).toBe(menuRecipe.SELECTED_SURFACE)
		local rows: { string } = {}
		for _, theme in THEMES do
			local ratio = contrast(roleColor(theme, paint.label), roleColor(theme, paint.fill))
			if ratio < FLOOR then
				error(
					`{theme.pkg}/{theme.name}: a selected menu row paints '{paint.label}' on '{tostring(paint.fill)}' `
						.. `at {round2(ratio)}:1, below {FLOOR}. The label of a row inside a card is a child `
						.. "`UI.Text`, and no `TextButton` rule in the sheet reaches one — so the card must "
						.. "pair the two itself (menu_recipe's CARD_CORNER note), and this pair does not read.",
					0
				)
			end
			table.insert(rows, `{theme.pkg}/{theme.name}@{round2(ratio)}`)
		end
		table.sort(rows)
		expect(table.concat(rows, " ")).toBe(
			"classic-desktop/Day@11.47 classic-desktop/Night@7.82 compact-pointer/Aqua@6.42 "
				.. "fantasy-ornate/Crypt@7.88 fantasy-ornate/Grand Hall@8.25 "
				.. "fantasy-parchment/Candlelight@6.48 fantasy-parchment/Daylight@6.92 "
				.. "glossy-mobile/Daylight@5.96 glossy-touch/Sky@6.36 pixel-quest/Quest@6.14 "
				.. "scifi-hud/Nightwatch@11.3"
		)
		-- ...and the row lets the claim go when it is no longer selected, so an
		-- UNSELECTED row is the theme's own content on the card, untouched
		local resting = cardRowPaint(false)
		expect(resting.fill).toBe(menuRecipe.RESTING_SURFACE)
		expect(resting.label).toBe("content")
		for _, theme in THEMES do
			expect(contrast(roleColor(theme, "content"), roleColor(theme, nil)) >= FLOOR).toBe(true)
		end
	end)

	it("4. CENSUS: what an UNPAIRED label reads at on each theme's selection fill", function()
		--[[ NOT A GATE ON THE PALETTES, and the difference matters. `content` on
			`controlSelected` is what a label paints when nothing pairs it — the
			reported defect exactly — and two themes are below the floor there BY
			CONSTRUCTION: their selected surface is a saturated plate, declared that
			way because `tests/theme_reference_packages.spec.luau` pins the
			declaration against the selection ART the package ships, and the art is a
			saturated plate. Neither palette is wrong; an unpaired label is.

			So this records the numbers and gates the SET: a third theme arriving
			below the floor is a fact somebody has to look at, and a theme LEAVING
			the list means its art or its palette moved. ]]
		local rows: { string } = {}
		local below: { string } = {}
		for _, theme in THEMES do
			local ratio = contrast(theme.colors.content, sheet_model.selectedSurfaceOf(theme))
			table.insert(rows, `{theme.pkg}/{theme.name}@{round2(ratio)}`)
			if ratio < FLOOR then
				table.insert(below, `{theme.pkg}/{theme.name}`)
			end
		end
		table.sort(rows)
		table.sort(below)
		expect(table.concat(rows, " ")).toBe(
			"classic-desktop/Day@10.24 classic-desktop/Night@7.17 compact-pointer/Aqua@8.89 "
				.. "fantasy-ornate/Crypt@7.82 fantasy-ornate/Grand Hall@8.34 "
				.. "fantasy-parchment/Candlelight@5.46 fantasy-parchment/Daylight@7.62 "
				.. "glossy-mobile/Daylight@11.69 glossy-touch/Sky@2.37 pixel-quest/Quest@2.46 "
				.. "scifi-hud/Nightwatch@9.33"
		)
		expect(table.concat(below, " ")).toBe("glossy-touch/Sky pixel-quest/Quest")
	end)
end)
