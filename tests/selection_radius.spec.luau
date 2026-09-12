--[[ THE HIGHLIGHT SHAPE IS A THEME TOKEN (user ruling 2026-09-12).

	`radii.selection` decides the shape of every selection highlight — the
	segmented picker's sliding fill and a menu card's chosen-row shade with the
	focus ring that sits on it. It follows `radii.control` unless a package
	authors it, and square art sets 0 in its OWN metrics: Facet never guesses a
	shape from a theme's name. This file proves the contract from the outside —
	a custom package built through the public compiler flips the token and both
	highlights follow with no code change — and pins the card row's clipped
	shape per position across a round theme, a rounded package and a square one. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local Facet = require("../src") :: any
local worldLib = require("./lib/world")
local snapshot = require("../src/themes/snapshot")
local styling = require("../src/tokens/styling")
local UI = Facet.UI

local function packageOf(name: string): any
	return (require)(`../examples/themes/{name}`).build(Facet.themes)
end
local function metricsOf(pkg: any): any
	return snapshot.resolve(pkg, nil, {})
end

-- a package a theme author could really ship: Facet Neutral with ONE token moved
local function customPackage(selection: number?): any
	local def: any = {
		base = snapshot.neutralPackage(),
		identity = {
			id = if selection == nil then "custom-follows" else `custom-selection-{selection}`,
			displayName = "Custom",
			schemaVersion = Facet.themes.SCHEMA,
			version = "1.0.0",
		},
	}
	if selection ~= nil then
		def.metrics = { radii = { selection = selection } }
	end
	local pkg, report = Facet.themes.define(def)
	assert(pkg ~= nil, `custom package rejected: {t.inspect and t.inspect(report) or tostring(report)}`)
	return pkg
end

local function suffixPath(w: any, suffix: string): string?
	for _, path in w.adapter.paths() do
		if string.sub(path, -#suffix) == suffix then
			return path
		end
	end
	return nil
end

local function cornerText(data: any, style: any?): string
	local painted = styling.paintCorners(data, style)
	if type(painted) ~= "table" then
		return "none"
	end
	if painted.radius ~= nil then
		return `uniform {painted.radius}`
	end
	return `tl {painted.topLeft} tr {painted.topRight} bl {painted.bottomLeft} br {painted.bottomRight}`
end

-- ===========================================================================
describe("radii.selection: the segmented fill follows the package's own token", function()
	local function stripWorld(metrics: any)
		local w = worldLib.new({
			viewport = { x = 0, y = 0, w = 640, h = 720 },
			safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
			themeMetrics = metrics,
		})
		local picker = Facet.Controls.Picker(w.core, {
			id = "View",
			selected = w.core:signal("a"),
			options = { { value = "a", label = "One" }, { value = "b", label = "Two" }, { value = "c", label = "Tri" } },
			env = w.env,
			presentation = "segmented",
		})
		w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
		w.pres.refresh()
		return w
	end
	local BAR = "/S/View/Indicator/Layer/Bar"

	it("a custom package that authors selection = 0 gets a square fill, one that omits it follows control", function()
		local follows = metricsOf(customPackage(nil))
		local square = metricsOf(customPackage(0))
		local wide = metricsOf(customPackage(14))
		expect(snapshot.resolveNumber(follows, "radii.selection")).toBe(
			snapshot.resolveNumber(follows, "radii.control")
		)
		expect(snapshot.resolveNumber(square, "radii.selection")).toBe(0)
		expect(snapshot.resolveNumber(wide, "radii.selection")).toBe(14)
		local w1 = stripWorld(follows)
		expect(cornerText(w1.adapter.node(BAR).props.corners, follows)).toBe(`uniform {follows.radii.control}`)
		local w2 = stripWorld(square)
		expect(cornerText(w2.adapter.node(BAR).props.corners, square)).toBe("uniform 0")
		local w3 = stripWorld(wide)
		expect(cornerText(w3.adapter.node(BAR).props.corners, wide)).toBe("uniform 14")
	end)

	it("the shipped square-art packages author it themselves; the rounded ones let it follow", function()
		for _, case in
			{
				{ name = "pixel_quest", want = 0 },
				{ name = "fantasy_ornate", want = 0 },
				{ name = "glossy_touch", want = 10 }, -- authored beside its floating shade inset
				{ name = "classic_desktop", want = nil },
			}
		do
			local pkg = packageOf(case.name)
			local metrics = metricsOf(pkg)
			local authored = pkg.metrics.radii.selection
			expect(`{case.name} authored: {tostring(authored)}`).toBe(`{case.name} authored: {tostring(case.want)}`)
			local effective = snapshot.resolveNumber(metrics, "radii.selection")
			local want = if case.want ~= nil then case.want else metrics.radii.control
			expect(`{case.name} effective: {effective}`).toBe(`{case.name} effective: {want}`)
		end
	end)
end)

-- ===========================================================================
describe("radii.selection: a menu card's row wears the card's clipped corners, shade and ring alike", function()
	local FACTS = {
		desktop = {
			viewport = { x = 0, y = 0, w = 1280, h = 720 },
			capabilities = { mouse = true, keyboard = true },
			preferredInput = "KeyboardAndMouse",
		},
	}
	local function menuWorld(metrics: any?, count: number)
		local facts: any = table.clone(FACTS.desktop)
		facts.themeMetrics = metrics
		local w = worldLib.new(facts)
		local options = {}
		for i = 1, count do
			table.insert(options, { value = `o{i}`, label = `Option {i}` })
		end
		local picker =
			Facet.Controls.Picker(w.core, { id = "P", selected = w.core:signal("o1"), options = options, env = w.env })
		w.present(UI.Screen({ id = "S", children = { picker.blueprint } }))
		w.pres.refresh()
		return w, picker
	end
	local function expectedRadius(metrics: any?): number
		local snap = metrics or snapshot.neutral()
		local selection = snapshot.resolveNumber(snap, "radii.selection") or 0
		local panel = snapshot.resolveNumber(snap, "radii.panel") or 0
		local insets = if type(snap.chromeInsets) == "table" then snap.chromeInsets.panel else nil
		local inset = if type(insets) == "table"
			then math.max(tonumber(insets.top) or 0, tonumber(insets.left) or 0)
			else 0
		return math.max(0, math.min(selection, panel - inset))
	end
	local function rows(w: any): { string }
		local out = {}
		for _, path in w.adapter.paths() do
			if string.match(path, "/Opt%-[^/]+%+background/Fill$") then
				table.insert(out, path)
			end
		end
		table.sort(out, function(a, b)
			return w.adapter.node(a).rect.y < w.adapter.node(b).rect.y
		end)
		return out
	end
	local function shapeOf(w: any, fillPath: string): string
		local c = w.adapter.node(fillPath).props.corners
		if type(c) ~= "table" then
			return "none"
		end
		if c.radius ~= nil then
			return `{c.radius},{c.radius},{c.radius},{c.radius}`
		end
		return `{c.topLeft or 0},{c.topRight or 0},{c.bottomLeft or 0},{c.bottomRight or 0}`
	end

	local THEMES = {
		{ id = "facet-neutral", metrics = nil },
		{ id = "pixel-quest", metrics = metricsOf(packageOf("pixel_quest")) },
	}

	it("first / middle / last / only rows take the card's top, none, bottom and all four corners", function()
		for _, theme in THEMES do
			local r = expectedRadius(theme.metrics)
			local w, picker = menuWorld(theme.metrics, 3)
			w.adapter.tap(suffixPath(w, "/Trigger") :: string)
			w.pres.refresh()
			expect(`{theme.id} open: {picker.dump().open}`).toBe(`{theme.id} open: true`)
			local fills = rows(w)
			expect(`{theme.id} rows: {#fills}`).toBe(`{theme.id} rows: 3`)
			expect(`{theme.id} first: {shapeOf(w, fills[1])}`).toBe(`{theme.id} first: {r},{r},0,0`)
			expect(`{theme.id} middle: {shapeOf(w, fills[2])}`).toBe(`{theme.id} middle: 0,0,0,0`)
			expect(`{theme.id} last: {shapeOf(w, fills[3])}`).toBe(`{theme.id} last: 0,0,{r},{r}`)
			-- the ROW wears the same corners as its shade, so the ring (the row's
			-- stroke) is the same clipped shape
			for _, fill in fills do
				local rowPath = string.gsub(
					fill,
					"%+background/Fill$",
					"+background/" .. string.match(fill, "(Opt%-[^/]+)%+background/Fill$")
				)
				local row = w.adapter.node(rowPath)
				expect(
					`{theme.id} row wears the shade's corners: {row ~= nil and row.props.corners == w.adapter.node(fill).props.corners}`
				).toBe(`{theme.id} row wears the shade's corners: true`)
			end
			local w1 = menuWorld(theme.metrics, 1)
			w1.adapter.tap(suffixPath(w1, "/Trigger") :: string)
			w1.pres.refresh()
			local only = rows(w1)
			expect(`{theme.id} only rows: {#only}`).toBe(`{theme.id} only rows: 1`)
			expect(`{theme.id} only: {shapeOf(w1, only[1])}`).toBe(`{theme.id} only: {r},{r},{r},{r}`)
		end
	end)

	it(
		"a square package (selection = 0) squares every row, and a custom package flips it with no code change",
		function()
			local square = metricsOf(customPackage(0))
			local w = menuWorld(square, 2)
			w.adapter.tap(suffixPath(w, "/Trigger") :: string)
			w.pres.refresh()
			local fills = rows(w)
			expect(shapeOf(w, fills[1])).toBe("0,0,0,0")
			expect(shapeOf(w, fills[2])).toBe("0,0,0,0")
			local round = metricsOf(customPackage(nil))
			local r = expectedRadius(round)
			expect(r > 0).toBe(true)
			local w2 = menuWorld(round, 2)
			w2.adapter.tap(suffixPath(w2, "/Trigger") :: string)
			w2.pres.refresh()
			local fills2 = rows(w2)
			expect(shapeOf(w2, fills2[1])).toBe(`{r},{r},0,0`)
			expect(shapeOf(w2, fills2[2])).toBe(`0,0,{r},{r}`)
		end
	)

	it(
		"a package that authors `controls.popup.shadeInset` gets the FLOATING form: inset on both sides, radii.selection on all four corners",
		function()
			-- Glossy Touch ships it (4px); a custom package flips it with the metric alone
			local customFloating = (function()
				local pkg = Facet.themes.define({
					base = snapshot.neutralPackage(),
					identity = {
						id = "custom-floating",
						displayName = "Custom",
						schemaVersion = Facet.themes.SCHEMA,
						version = "1.0.0",
					},
					metrics = { controls = { popup = { triggerHeight = 40, shadeInset = 6 } } },
				})
				assert(pkg ~= nil, "custom floating package rejected")
				return metricsOf(pkg)
			end)()
			for _, case in
				{
					{ id = "glossy-touch", metrics = metricsOf(packageOf("glossy_touch")), inset = 4 },
					{ id = "custom-floating", metrics = customFloating, inset = 6 },
				}
			do
				expect(`{case.id} shadeInset: {snapshot.resolveNumber(case.metrics, "controls.popup.shadeInset")}`).toBe(
					`{case.id} shadeInset: {case.inset}`
				)
				local selection = snapshot.resolveNumber(case.metrics, "radii.selection")
				local w, picker = menuWorld(case.metrics, 3)
				w.adapter.tap(suffixPath(w, "/Trigger") :: string)
				w.pres.refresh()
				expect(`{case.id} open: {picker.dump().open}`).toBe(`{case.id} open: true`)
				local list = w.adapter.node(suffixPath(w, "/List") :: string).rect
				for _, fill in rows(w) do
					local node = w.adapter.node(fill)
					expect(`{case.id} inset: {node.rect.x - list.x},{list.x + list.w - (node.rect.x + node.rect.w)}`).toBe(
						`{case.id} inset: {case.inset},{case.inset}`
					)
					local c = node.props.corners
					expect(`{case.id} corners token: {c and c.tokens and c.tokens.radius}`).toBe(
						`{case.id} corners token: selection`
					)
					expect(`{case.id} painted: {styling.paintCorners(c, case.metrics).radius}`).toBe(
						`{case.id} painted: {selection}`
					)
					local rowPath = string.gsub(
						fill,
						"%+background/Fill$",
						"+background/" .. string.match(fill, "(Opt%-[^/]+)%+background/Fill$")
					)
					local row = w.adapter.node(rowPath)
					expect(
						`{case.id} row matches: {row.props.corners == c and row.rect.x == node.rect.x and row.rect.w == node.rect.w}`
					).toBe(`{case.id} row matches: true`)
				end
			end
			-- the flush form is still the default: neutral authors no inset
			expect(snapshot.resolveNumber(snapshot.neutral(), "controls.popup.shadeInset") or 0).toBe(0)
		end
	)

	it("a pointer open shows the shade only; navigation focus paints the ring on the same clipped row", function()
		local w, picker = menuWorld(nil, 3)
		w.adapter.tap(suffixPath(w, "/Trigger") :: string)
		w.pres.refresh()
		expect(picker.dump().open).toBe(true)
		-- the tap set the pointer origin, so the focus ring does not paint
		expect(w.pres.focus.focusVisible:get()).toBe(false)
		local chosenFill = rows(w)[1]
		local chosenRow = string.gsub(chosenFill, "/Fill$", "/Opt-o1")
		expect(w.adapter.node(chosenRow).focused ~= true).toBe(true)
		-- a navigation act brings the ring back, on the row's own clipped corners
		w.pres.focus.setFocusOrigin("navigation")
		w.pres.refresh()
		expect(w.pres.focus.focusVisible:get()).toBe(true)
		expect(w.adapter.node(chosenRow).focused).toBe(true)
		expect(w.adapter.node(chosenRow).props.corners == w.adapter.node(chosenFill).props.corners).toBe(true)
		expect(shapeOf(w, chosenFill)).toBe(`{expectedRadius(nil)},{expectedRadius(nil)},0,0`)
	end)
end)
