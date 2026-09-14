--!strict
--[[ A HAIRLINE IS A HAIRLINE WHEREVER IT IS DRAWN.

	WHAT WAS REPORTED (owner, 2026-09-12, Facet Neutral): the seam between two
	segments of an icon picker is a BRIGHT WHITE BAR — louder than the labels
	beside it, and the loudest thing in the strip.

	WHAT IT ACTUALLY WAS. Facet Neutral's `extra.hairline` is `rgb(255, 255, 255)`
	and its own comment says what it is for: "used at 8% opacity". Every hairline
	in the system spends that opacity — `Raised panel — hairline`, `Chip outline`,
	the slot outlines — through `extra.hairlineOpacity` (0.92 as a Transparency).
	The `Divider` rule spent the COLOUR and threw the opacity away:

	    props = { BackgroundColor3 = "$Hairline", BackgroundTransparency = num(0) }

	So one subsystem drew the theme's hairline at 8% and another drew the same
	token at 100%, and the second one is every `UI.Divider` on screen: the
	segmented picker's seam, `Controls.Menu`'s row rule, `SplitButton`'s divider,
	and any list separator a screen declares. The bespoke (non-native) path in
	`screen_target` had the identical pair of writes and the identical omission.

	THE FIX IS THE TOKEN THE THEME ALREADY AUTHORED. The divider spends
	`hairlineOpacity`, so every package inherits a subtle seam without editing a
	line, and a package that wants a louder one says so once — in the same number
	that decides its panel strokes, which is what keeps a hairline one decision.

	WHAT IS PINNED HERE:

	  1. The two compiled builders agree with themselves: a divider spends exactly
	     the transparency the panel's own hairline stroke spends, in every theme of
	     every shipped package and in the base seed.
	  2. The CONSEQUENCE, resolved as colour: composited over the surface it sits
	     on, a divider differs from that surface by less than the theme's own
	     secondary content does. That is the report's sentence — "slightly lighter
	     than the surface it sits on, never the bright contentSecondary" — as a
	     measurement rather than as a rule about a number.
	  3. The bespoke path writes the same pair, so a target running without native
	     paint draws the same seam.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local sheet_model = require("../src/tokens/sheet_model")
local default_style = require("../src/tokens/default_style")
local adapterSource = require("./lib/adapter_source")

local PACKAGES: { { name: string, module: any } } = {
	{ name = "classic_desktop", module = require("../examples/themes/classic_desktop") },
	{ name = "compact_pointer", module = require("../examples/themes/compact_pointer") },
	{ name = "fantasy_ornate", module = require("../examples/themes/fantasy_ornate") },
	{ name = "fantasy_parchment", module = require("../examples/themes/fantasy_parchment") },
	{ name = "glossy_mobile", module = require("../examples/themes/glossy_mobile") },
	{ name = "glossy_touch", module = require("../examples/themes/glossy_touch") },
	{ name = "pixel_quest", module = require("../examples/themes/pixel_quest") },
	{ name = "scifi_hud", module = require("../examples/themes/scifi_hud") },
}

local compiled: { { label: string, model: any, theme: any } }? = nil
local function models(): { { label: string, model: any, theme: any } }
	if compiled ~= nil then
		return compiled
	end
	local out: { { label: string, model: any, theme: any } } = {}
	local neutral = sheet_model.build({ themes = { { name = "Facet Neutral", style = default_style } } })
	table.insert(out, { label = "Facet Neutral", model = neutral, theme = neutral.themes[1] })
	for _, entry in PACKAGES do
		local package, report = entry.module.build(Facet.themes)
		assert(package ~= nil, `{entry.name} failed its own package gate: {report and report.errors[1]}`)
		local model = sheet_model.buildPackage(package, {})
		for _, theme in model.themes do
			table.insert(out, { label = `{entry.name}/{theme.name}`, model = model, theme = theme })
		end
	end
	compiled = out
	return out
end

local function ruleNamed(model: any, name: string): any
	for _, rule in model.rules do
		if rule.name == name then
			return rule
		end
	end
	error(`no rule named '{name}'`)
end

local function numberOf(value: any): number?
	if type(value) == "table" and value.kind == "number" then
		return value.value
	end
	return nil
end

local function colourOf(theme: any, value: any): { r: number, g: number, b: number }
	local resolved = if type(value) == "string" and string.sub(value, 1, 1) == "$"
		then theme.tokens[string.sub(value, 2)]
		else value
	assert(type(resolved) == "table" and type(resolved.r) == "number", `not a colour: {tostring(value)}`)
	return { r = resolved.r, g = resolved.g, b = resolved.b }
end

-- how far apart two colours are, as the largest per-channel difference. Crude on
-- purpose: this spec is asking "is one of these shouting", not grading contrast.
local function distance(a: { r: number, g: number, b: number }, b: { r: number, g: number, b: number }): number
	return math.max(math.abs(a.r - b.r), math.abs(a.g - b.g), math.abs(a.b - b.b))
end

local function over(
	fill: { r: number, g: number, b: number },
	ground: { r: number, g: number, b: number },
	transparency: number
): { r: number, g: number, b: number }
	local alpha = 1 - transparency
	return {
		r = ground.r + (fill.r - ground.r) * alpha,
		g = ground.g + (fill.g - ground.g) * alpha,
		b = ground.b + (fill.b - ground.b) * alpha,
	}
end

describe("divider hairline: one opacity for every hairline", function()
	it("a divider spends the transparency the panel's own hairline stroke spends", function()
		for _, entry in models() do
			local divider = numberOf(ruleNamed(entry.model, "Divider").props.BackgroundTransparency)
			local stroke = numberOf(ruleNamed(entry.model, "Raised panel — hairline").props.Transparency)
			assert(divider ~= nil and stroke ~= nil, `{entry.label}: a hairline rule carries no number`)
			assert(
				divider == stroke,
				`{entry.label}: divider spends {divider} where the panel hairline spends {stroke}`
			)
		end
		expect(#models() > 8).toBe(true)
	end)

	it("Facet Neutral's hairline really is pure white, which is why the seam was a white bar", function()
		local neutral = models()[1]
		local hairline = colourOf(neutral.theme, "$Hairline")
		expect(hairline.r).toBe(1)
		expect(hairline.g).toBe(1)
		expect(hairline.b).toBe(1)
	end)
end)

--[[ A PACKAGE THAT AUTHORED A BOLD HAIRLINE KEEPS IT. Pixel Quest's is `INK` at
	`hairlineOpacity = 0.2` — 80% visible, and its panel strokes are 4px of the
	same ink — because a washed 1px rule is not a thing pixel art has. The rule
	above is what makes that a THEME's decision and not the framework's: a bold
	seam and a bold stroke are the same number. So this file measures the seam's
	loudness only where the theme asked for a wash, and censuses the bold ones so
	a package that ships a bright seam by accident is still seen. ]]
local BOLD = 0.5

describe("divider hairline: the seam is quieter than the words beside it", function()
	it("composited over its surface, a washed divider moves it less than secondary content does", function()
		local washed = 0
		for _, entry in models() do
			local rule = ruleNamed(entry.model, "Divider")
			local transparency = numberOf(rule.props.BackgroundTransparency) :: number
			if transparency < BOLD then
				continue
			end
			washed += 1
			local hairline = colourOf(entry.theme, rule.props.BackgroundColor3)
			for _, ground in { "Control", "Surface", "SurfaceStrong" } do
				local under = colourOf(entry.theme, `${ground}`)
				local seam = distance(over(hairline, under, transparency), under)
				local words = distance(colourOf(entry.theme, "$ContentSecondary"), under)
				assert(seam > 0, `{entry.label}: the divider is invisible on {ground}`)
				assert(
					seam < words,
					`{entry.label}: on {ground} the seam moves the surface by {seam}, `
						.. `secondary content by {words} — the seam is the louder of the two`
				)
			end
		end
		expect(washed >= #models() - 1).toBe(true)
	end)

	it("and the only theme that authored a bold one is the pixel package", function()
		local bold: { string } = {}
		for _, entry in models() do
			local transparency = numberOf(ruleNamed(entry.model, "Divider").props.BackgroundTransparency) :: number
			if transparency < BOLD then
				table.insert(bold, entry.label)
			end
		end
		expect(table.concat(bold, ",")).toBe("pixel_quest/Quest")
	end)
end)

describe("divider hairline: the bespoke path draws the same seam", function()
	it("screen_target's non-native Divider branch spends the theme's hairline opacity", function()
		local source = adapterSource.live()
		expect(string.find(source, "instance.BackgroundColor3 = COLOR.hairline", 1, true) ~= nil).toBe(true)
		expect(string.find(source, "instance.BackgroundTransparency = style.extra.hairlineOpacity", 1, true) ~= nil).toBe(
			true
		)
	end)
end)
