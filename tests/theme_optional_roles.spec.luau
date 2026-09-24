--!strict
-- OPTIONAL PALETTE ROLES a theme may author in `extra`: `selection` /
-- `onSelection` (the ink an ON or chosen indicator paints) and `scrim` (the colour
-- a modal backdrop dims toward). Unauthored, each resolves to what the framework
-- painted before, so Facet Neutral is unchanged; authored, every consumer follows.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")
local sheet_model = require("../src/tokens/sheet_model")
local snapshot = require("../src/themes/snapshot")
local themes = Facet.themes

local INK = { r = 0.97, g = 0.97, b = 0.98 }
local ON_INK = { r = 0.07, g = 0.07, b = 0.08 }
local VEIL = { r = 0.05, g = 0.05, b = 0.06 }

local function authored(extra: any): any
	local neutral = snapshot.neutralPackage()
	local dark = neutral.style.themes[1]
	local pkg, report = themes.define({
		base = neutral,
		identity = { id = "roles", displayName = "Roles", schemaVersion = themes.SCHEMA, version = "1.0.0" },
		style = { defaultTheme = "Ink", themes = { { name = "Ink", colors = dark.colors, extra = extra } } },
	})
	assert(pkg ~= nil, "define failed: " .. tostring(report and report.errors[1] and report.errors[1].message))
	return pkg
end

local function ruleNamed(model: any, name: string): any
	for _, rule in model.rules do
		if rule.name == name then
			return rule
		end
	end
	return nil
end

local function same(a: any, b: any): boolean
	return math.abs(a.r - b.r) < 1e-6 and math.abs(a.g - b.g) < 1e-6 and math.abs(a.b - b.b) < 1e-6
end

describe("optional palette roles: unauthored keeps today's paint", function()
	it("Neutral's selection ink is its accent pair and its scrim is its surface", function()
		local model = sheet_model.buildPackage(snapshot.neutralPackage())
		for _, theme in model.themes do
			expect(same(theme.tokens.Selection, theme.tokens.Accent)).toBe(true)
			expect(same(theme.tokens.OnSelection, theme.tokens.OnAccent)).toBe(true)
			expect(same(theme.tokens.Scrim, theme.tokens.Surface)).toBe(true)
		end
		expect(ruleNamed(model, sheet_model.SCRIM_RULE).props.BackgroundColor3).toBe("$Scrim")
		local palette = sheet_model.togglePalette(snapshot.neutralPackage().style.themes[1])
		expect(same(palette.trackOn, snapshot.neutralPackage().style.themes[1].colors.accent)).toBe(true)
	end)
end)

describe("optional palette roles: authored, every consumer follows", function()
	local pkg = authored({ selection = INK, onSelection = ON_INK, scrim = VEIL })
	local theme = pkg.style.themes[1]

	it("the sheet tokens, the tint vocabulary and the switch palette carry the authored colours", function()
		local model = sheet_model.buildPackage(pkg)
		expect(same(model.themes[1].tokens.Selection, INK)).toBe(true)
		expect(same(model.themes[1].tokens.OnSelection, ON_INK)).toBe(true)
		expect(same(model.themes[1].tokens.Scrim, VEIL)).toBe(true)
		expect(same(sheet_model.tintColor(theme, { role = "selection", blend = 1 }, "Box"), INK)).toBe(true)
		expect(same(sheet_model.tintColor(theme, { role = "onSelection", blend = 1 }, "Text"), ON_INK)).toBe(true)
		local palette = sheet_model.togglePalette(theme)
		expect(same(palette.trackOn, INK)).toBe(true)
		expect(same(palette.knobOn, ON_INK)).toBe(true)
	end)

	it("a Slider's fill and a TabView's underline paint the selection ink", function()
		local w = require("./lib/world").new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
		w.app.installTheme(pkg)
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				UI.VStack("Col")({
					width = UI.fill(),
					UI.Slider("Vol")({ value = Compose.cell(0.5), min = 0, max = 1 }),
					UI.TabView("Tabs")({
						placement = "topBar",
						indicator = "underline",
						selection = Compose.cell("a"),
						tabs = {
							{
								id = "a",
								label = "A",
								content = function()
									return UI.Text("PA")({ text = "A" })
								end,
							},
							{
								id = "b",
								label = "B",
								content = function()
									return UI.Text("PB")({ text = "B" })
								end,
							},
						},
					}),
				}),
			})
		end)
		w.settle(10)
		local fill, bar
		for _, path in w.adapter.paths() do
			if string.match(path, "/Vol.*/Fill$") then
				fill = w.adapter.node(path)
			elseif string.match(path, "/Tabs.*/Bar$") then
				bar = w.adapter.node(path)
			end
		end
		expect(fill).never().toBeNil()
		expect(fill.tintSpec.role).toBe("selection")
		expect(same(fill.tintColor, INK)).toBe(true)
		expect(bar).never().toBeNil()
		expect(bar.tintSpec.role).toBe("selection")
		expect(same(bar.tintColor, INK)).toBe(true)
	end)
end)

describe("the selection mark: a chosen chip and a checked box wear an AUTHORED selection ink", function()
	local function indexOf(model: any, name: string): number
		for i, rule in model.rules do
			if rule.name == name then
				return i
			end
		end
		return -1
	end

	it("no theme that leaves `selection` out gets a mark rule; an authoring one gets all four, hover last", function()
		local neutral = sheet_model.buildPackage(snapshot.neutralPackage())
		expect(ruleNamed(neutral, "Selection mark — chosen")).toBeNil()
		expect(
			ruleNamed(
				sheet_model.build({ themes = { { name = "N", style = require("../src/tokens/default_style") } } }),
				"Selection mark — chosen"
			)
		).toBeNil()
		local model = sheet_model.buildPackage(authored({ selection = INK, onSelection = ON_INK }))
		local chosen = ruleNamed(model, "Selection mark — chosen")
		expect(chosen.selector).toBe("TextButton.facet-selected.facet-selection-mark")
		expect(chosen.props.BackgroundColor3).toBe("$Selection")
		expect(chosen.props.TextColor3).toBe("$OnSelection")
		expect(ruleNamed(model, "Selection mark — fill").selector).toBe("Frame.facet-selection-mark")
		expect(ruleNamed(model, "Selection mark — ink").props.TextColor3).toBe("$OnSelection")
		expect(indexOf(model, "Selection mark — chosen") > indexOf(model, "Selected row")).toBe(true)
		local hover = indexOf(model, "Selection mark — chosen hover")
		expect(hover > indexOf(model, "Selected — hover")).toBe(true)
		expect(hover > indexOf(model, "Utility — hover")).toBe(true)
		expect(sheet_model.classifyTags({ selectionMark = true })["facet-selection-mark"]).toBe(true)
	end)

	it("a Chip and a checkbox Toggle carry the mark; the checkbox fill shows only while checked", function()
		local w = require("./lib/world").new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
		local UI = w.UI
		local on = Compose.cell(false)
		w.present(function()
			return UI.Screen("S")({
				UI.VStack("Col")({
					UI.Chip("Pick")({ label = "Pick", selected = Compose.cell(true) }),
					UI.Toggle("Check")({ label = "Check", presentation = "checkbox", value = on }),
				}),
			})
		end)
		w.settle(5)
		local function find(pattern: string): any
			for _, path in w.adapter.paths() do
				if string.match(path, pattern) then
					return w.adapter.node(path)
				end
			end
			return nil
		end
		expect(find("/Pick$").decorationHint.selectionMark).toBe(true)
		local fill = find("/Indicator/Fill$")
		expect(fill.decorationHint.selectionMark).toBe(true)
		expect(fill.visible).toBe(false)
		on:set(true)
		w.settle(5)
		expect(find("/Indicator/Fill$").visible).toBe(true)
		expect(find("/Indicator/Check$").decorationHint.selectionMark).toBe(true)
	end)
end)
