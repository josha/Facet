--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local Rules = require("../src/ui/review_rules")

type Element = Rules.ReviewElement
type Options = {
	text: string?,
	size: number?,
	bold: boolean?,
	font: string?,
	fill: Rules.ReviewColor?,
	opaque: boolean?,
	interactive: boolean?,
	image: boolean?,
	visible: boolean?,
	ink: Rules.ReviewRect?,
	clips: boolean?,
	fan: boolean?,
	z: number?,
	turn: number?,
	native: boolean?,
	paint: Rules.ReviewRect?,
	ground: boolean?,
}

local DARK = { r = 0.08, g = 0.09, b = 0.12 }
local PANEL = { r = 0.12, g = 0.14, b = 0.2 }
local WHITE = { r = 1, g = 1, b = 1 }

local function scene()
	local elements: { Element } = {}
	local function add(
		parent: number?,
		class: string,
		x: number,
		y: number,
		w: number,
		h: number,
		options: Options?
	): number
		local given: Options = options or {}
		local element: Element = {
			index = #elements + 1,
			parent = parent,
			class = class,
			path = ("Gui.%s%d"):format(class, #elements + 1),
			rect = { x = x, y = y, width = w, height = h },
			visible = given.visible ~= false,
			interactive = given.interactive == true,
			fill = given.fill or DARK,
			fillTransparency = if given.opaque then 0 else 1,
			image = given.image == true,
			clips = given.clips,
			fan = given.fan,
			z = given.z,
			turn = given.turn,
			paint = given.paint,
			ground = given.ground,
		}
		if given.text ~= nil then
			element.text = {
				content = given.text,
				size = given.size or 18,
				bold = given.bold == true,
				font = given.font or "BuilderSans",
				color = WHITE,
				transparency = 0,
				ink = given.ink,
				native = given.native,
			}
		end
		table.insert(elements, element)
		return element.index
	end
	local function snapshot(): Rules.ReviewSnapshot
		return { width = 1920, height = 1080, elements = elements }
	end
	return add, snapshot
end

local function rules(report: Rules.ReviewReport): { [string]: number }
	local counts: { [string]: number } = {}
	for _, finding in report.findings do
		counts[finding.rule] = (counts[finding.rule] or 0) + 1
	end
	return counts
end

return function(harness: Verify.Harness)
	harness:case("segments split spaced separators and keep compact values whole", function(t)
		t:expect(#Rules.segments("Wins 0 · Losses 0 · Draws 0")):toBe(3)
		t:expect(#Rules.segments("Ion Motor • 500 credits")):toBe(2)
		t:expect(#Rules.segments("Motors / +8 top speed")):toBe(2)
		t:expect(#Rules.segments("XP 0/300")):toBe(1)
		t:expect(#Rules.segments("Rock-solid grip")):toBe(1)
	end)

	harness:case("the rank card reports joined facts, competing peaks and a zero wall", function(t)
		local add, snapshot = scene()
		local page = add(nil, "Frame", 0, 0, 1920, 1080, { opaque = true, fill = DARK })
		local card = add(page, "Frame", 32, 300, 800, 280, { opaque = true, fill = PANEL })
		add(card, "TextLabel", 60, 330, 200, 40, { text = "Quick", size = 32, bold = true })
		add(card, "TextLabel", 60, 380, 300, 40, { text = "Spark · 1000", size = 32, bold = true })
		add(card, "TextLabel", 60, 440, 400, 20, { text = "Wins 0 · Losses 0 · Draws 0", size = 18 })
		add(card, "TextLabel", 60, 480, 400, 20, { text = "Provisional · 0 of 10 ranked games", size = 18 })
		local counts = rules(Rules.analyze(snapshot()))
		t:expect(counts["joined-facts"]):toBe(3)
		t:expect(counts["competing-peaks"]):toBe(1)
		t:expect(counts["zero-wall"]):toBe(1)
	end)

	harness:case("a separated stat block reports no joined facts and no zero wall", function(t)
		local add, snapshot = scene()
		local page = add(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
		add(page, "TextLabel", 60, 60, 300, 20, { text = "QUICK", size = 15, bold = true })
		add(page, "TextLabel", 60, 90, 300, 64, { text = "1000", size = 56, bold = true })
		add(page, "TextLabel", 60, 160, 300, 20, { text = "Spark tier", size = 18 })
		add(page, "TextLabel", 60, 200, 300, 20, { text = "Play 10 ranked games to get your rank", size = 18 })
		add(page, "TextLabel", 60, 240, 300, 20, { text = "Best streak", size = 15 })
		add(page, "TextLabel", 60, 260, 300, 28, { text = "4", size = 28, bold = true })
		local counts = rules(Rules.analyze(snapshot()))
		t:expect(counts["joined-facts"]):toBe(nil)
		t:expect(counts["zero-wall"]):toBe(nil)
		t:expect(counts["flat-hierarchy"]):toBe(nil)
		t:expect(counts["numbers-unemphasized"]):toBe(nil)
	end)

	harness:case("phrases without numbers are low and short hints pass", function(t)
		local add, snapshot = scene()
		add(nil, "TextLabel", 0, 0, 400, 20, { text = "Drag to explore · Pinch to zoom" })
		add(nil, "TextLabel", 0, 40, 400, 20, { text = "Common · Balanced · Light" })
		local report = Rules.analyze(snapshot())
		t:expect(#report.findings):toBe(1)
		t:expect(report.findings[1].rule):toBe("joined-facts")
		t:expect(report.findings[1].severity):toBe("low")
	end)

	harness:case("numbers at body size without weight are unemphasized", function(t)
		local add, snapshot = scene()
		add(nil, "TextLabel", 0, 0, 400, 40, { text = "Parts lab", size = 40, bold = true })
		for row = 1, 4 do
			add(nil, "TextLabel", 0, 60 * row, 400, 20, { text = ("%d credits"):format(row * 100), size = 18 })
		end
		t:expect(rules(Rules.analyze(snapshot()))["numbers-unemphasized"]):toBe(1)
	end)

	harness:case("flat type reports one flat hierarchy at the largest text", function(t)
		local add, snapshot = scene()
		add(nil, "TextLabel", 0, 0, 400, 20, { text = "Garage", size = 20, bold = true })
		for row = 1, 5 do
			add(nil, "TextLabel", 0, 40 * row, 400, 20, { text = "Row " .. row, size = 18 })
		end
		local report = Rules.analyze(snapshot())
		local found: Rules.ReviewFinding? = nil
		for _, finding in report.findings do
			if finding.rule == "flat-hierarchy" then
				found = finding
			end
		end
		t:expect(found ~= nil):toBe(true)
		t:expect((found :: Rules.ReviewFinding).path):toBe("Gui.TextLabel1")
	end)

	harness:case("repeated records without a visual are reported and art removes the finding", function(t)
		local function rows(image: boolean, plated: boolean): { [string]: number }
			local add, snapshot = scene()
			local list = add(nil, "Frame", 0, 0, 1000, 600)
			for row = 1, 4 do
				local record = add(
					list,
					if plated then "TextButton" else "Frame",
					0,
					row * 70,
					1000,
					64,
					{ opaque = plated, fill = PANEL, interactive = plated }
				)
				add(record, "TextLabel", 10, row * 70 + 10, 300, 20, { text = "Part " .. row })
				add(record, "TextLabel", 10, row * 70 + 34, 300, 20, { text = "+8 speed" })
				if image then
					add(record, "ImageLabel", 900, row * 70 + 8, 48, 48, { image = true })
				end
			end
			return rules(Rules.analyze(snapshot()))
		end
		t:expect(rows(false, true)["record-without-visual"]):toBe(1)
		t:expect(rows(false, false)["record-without-visual"]):toBe(nil)
		t:expect(rows(true, true)["record-without-visual"]):toBe(nil)
	end)

	harness:case("a row of one-word buttons is not a set of records", function(t)
		local add, snapshot = scene()
		local bar = add(nil, "Frame", 0, 0, 600, 44)
		for column = 1, 4 do
			local button = add(bar, "TextButton", column * 150, 0, 140, 44, { opaque = true, interactive = true })
			add(button, "TextLabel", column * 150 + 10, 10, 100, 20, { text = "Tab " .. column })
		end
		t:expect(rules(Rules.analyze(snapshot()))["record-without-visual"]):toBe(nil)
	end)

	harness:case("a plate in a plate of nearly the same color is a nested surface", function(t)
		local add, snapshot = scene()
		local outer = add(nil, "Frame", 0, 0, 800, 600, { opaque = true, fill = PANEL })
		local inner = add(outer, "Frame", 20, 20, 760, 200, { opaque = true, fill = { r = 0.14, g = 0.16, b = 0.22 } })
		add(inner, "TextLabel", 40, 40, 300, 20, { text = "Word language" })
		t:expect(rules(Rules.analyze(snapshot()))["nested-surface"]):toBe(1)
	end)

	harness:case("hidden and transparent text is ignored", function(t)
		local add, snapshot = scene()
		local hidden = add(nil, "Frame", 0, 0, 400, 400, { visible = false })
		add(hidden, "TextLabel", 0, 0, 400, 20, { text = "Wins 0 · Losses 0", visible = false })
		t:expect(#Rules.analyze(snapshot()).findings):toBe(0)
	end)

	harness:case("the report lists prominence, sizes and only the fixes it uses", function(t)
		local add, snapshot = scene()
		add(nil, "TextLabel", 0, 0, 400, 20, { text = "Ion Motor • 500 credits", size = 18 })
		add(nil, "TextLabel", 0, 40, 400, 40, { text = "Parts lab", size = 40, bold = true })
		local report = Rules.analyze(snapshot())
		t:expect(report.prominence[1].content):toBe("Parts lab")
		t:expect(#report.sizes):toBe(2)
		t:expect(report.fixes["joined-facts"] ~= nil):toBe(true)
		t:expect(report.fixes["record-without-visual"]):toBe(nil)
		t:expect(string.find(report.text, "joined-facts", 1, true) ~= nil):toBe(true)
	end)

	harness:case("define reports a flat type scale as advice and stays valid", function(t)
		local themes = require("../src").themes
		local flatDefinition: Facet.ThemeDefinition = { identity = { id = "flat" } }
		local flat, flatReport = themes.define(flatDefinition)
		t:expect(flat ~= nil and flatReport.ok):toBe(true)
		local fields: { [string]: boolean } = {}
		for _, item in flatReport.advice do
			fields[item.field] = true
		end
		t:expect(fields["metrics.typography.numeral"]):toBe(true)
		local ThemeTypes = require("../src/ui/theme_types")
		local tuned: ThemeTypes.ThemeDefinition = {
			identity = { id = "tuned" },
			metrics = {
				typography = {
					body = { size = 18 },
					caption = { size = 15 },
					heading = { size = 24 },
					title = { size = 32 },
					numeral = { size = 32 },
				},
			},
		}
		local _, tunedReport = themes.define(tuned)
		t:expect(tunedReport.ok):toBe(true)
		t:expect(#tunedReport.advice):toBe(0)
		local refusedPackage, refused = themes.define((5 :: unknown) :: ThemeTypes.ThemeDefinition)
		t:expect(refusedPackage == nil and not refused.ok):toBe(true)
		t:expect(#refused.advice):toBe(0)
	end)

	harness:case("define advises when only one role carries the display family", function(t)
		local themes = require("../src").themes
		local ThemeTypes = require("../src/ui/theme_types")
		local function typography(roles: { string }): { [string]: ThemeTypes.TypographyPatch }
			local function role(name: string, size: number): ThemeTypes.TypographyPatch
				if table.find(roles, name) then
					return {
						size = size,
						font = { family = "rbxasset://fonts/families/Michroma.json", weight = "Bold" },
					}
				end
				return { size = size }
			end
			return {
				body = role("body", 18),
				caption = role("caption", 15),
				heading = role("heading", 24),
				numeral = role("numeral", 32),
				title = role("title", 32),
			}
		end
		local singleDefinition: Facet.ThemeDefinition =
			{ identity = { id = "single" }, metrics = { typography = typography({ "title" }) } }
		local _, single = themes.define(singleDefinition)
		local fields: { [string]: boolean } = {}
		for _, item in single.advice do
			fields[item.field] = true
		end
		t:expect(fields["metrics.typography.title"]):toBe(true)
		local carriedDefinition: Facet.ThemeDefinition = {
			identity = { id = "carried" },
			metrics = { typography = typography({ "title", "heading", "numeral" }) },
		}
		local _, carried = themes.define(carriedDefinition)
		t:expect(#carried.advice):toBe(0)
	end)

	harness:case("ranges, ratios, bullet lists and times are not joined facts", function(t)
		t:expect(#Rules.segments("Lap 2 / 3")):toBe(1)
		t:expect(#Rules.segments("HP 80 / 100")):toBe(1)
		t:expect(#Rules.segments("Level 5 – 10")):toBe(1)
		local add, snapshot = scene()
		add(nil, "TextLabel", 0, 0, 400, 60, { text = "• +10 speed\n• +5 grip\n• +2 boost" })
		add(nil, "TextLabel", 0, 80, 400, 20, { text = "00:00:00" })
		add(nil, "TextLabel", 0, 120, 400, 20, { text = "Lap 2 / 3" })
		local counts = rules(Rules.analyze(snapshot()))
		t:expect(counts["joined-facts"]):toBe(nil)
		t:expect(counts["zero-wall"]):toBe(nil)
	end)

	harness:case("parallel values in sibling groups are not competing peaks", function(t)
		local add, snapshot = scene()
		local card = add(nil, "Frame", 0, 0, 900, 300, { opaque = true, fill = PANEL })
		for column, name in { "Wins", "Losses", "Draws" } do
			local block = add(card, "Frame", column * 200, 20, 160, 120)
			local value = add(
				block,
				"TextLabel",
				column * 200,
				20,
				160,
				56,
				{ text = tostring(column * 3), size = 48, bold = true }
			)
			local _ = value
			add(block, "TextLabel", column * 200, 80, 160, 20, { text = name, size = 15 })
		end
		t:expect(rules(Rules.analyze(snapshot()))["competing-peaks"]):toBe(nil)
	end)

	harness:case("short choices stacked in a wide space are stacked choices", function(t)
		local add, snapshot = scene()
		local panel = add(nil, "Frame", 0, 0, 400, 700, { opaque = true, fill = PANEL })
		local stack = add(panel, "Frame", 20, 100, 360, 360)
		for row, name in { "Red", "Amber", "Green", "Cyan", "Blue", "Violet" } do
			add(stack, "TextButton", 20, 100 + (row - 1) * 56, 80, 48, { text = name, interactive = true })
		end
		t:expect(rules(Rules.analyze(snapshot()))["stacked-choices"]):toBe(1)
	end)

	harness:case("a wrapping row and a hugging menu column are not stacked choices", function(t)
		local add, snapshot = scene()
		local panel = add(nil, "Frame", 0, 0, 400, 700, { opaque = true, fill = PANEL })
		local row = add(panel, "Frame", 20, 100, 360, 110)
		for index, name in { "Red", "Amber", "Green", "Cyan", "Blue", "Violet" } do
			local column = (index - 1) % 3
			local line = (index - 1) // 3
			add(row, "TextButton", 20 + column * 116, 100 + line * 56, 108, 48, { text = name, interactive = true })
		end
		local menu = add(panel, "Frame", 120, 300, 160, 240)
		for index, name in { "Play", "Garage", "Shop", "Settings" } do
			add(menu, "TextButton", 120, 300 + (index - 1) * 60, 160, 52, { text = name, interactive = true })
		end
		t:expect(rules(Rules.analyze(snapshot()))["stacked-choices"]):toBe(nil)
	end)

	harness:case("a large card whose content fills one corner is a hollow plate", function(t)
		local add, snapshot = scene()
		local page = add(nil, "Frame", 0, 0, 1920, 1080)
		for row = 0, 2 do
			local card = add(page, "Frame", 40, 120 + row * 200, 1100, 180, { opaque = true, fill = PANEL })
			add(card, "TextLabel", 60, 140 + row * 200, 200, 30, { text = "Flux motor", size = 22, bold = true })
			add(card, "TextButton", 60, 190 + row * 200, 120, 44, { text = "Buy", interactive = true })
		end
		t:expect(rules(Rules.analyze(snapshot()))["hollow-plate"]):toBe(1)
	end)

	harness:case("a tile whose content spans it is not hollow", function(t)
		local add, snapshot = scene()
		local card = add(nil, "Frame", 40, 120, 320, 200, { opaque = true, fill = PANEL })
		add(card, "TextLabel", 56, 136, 200, 30, { text = "Flux motor", size = 22, bold = true })
		add(card, "TextLabel", 56, 180, 120, 44, { text = "+8", size = 40, bold = true })
		add(card, "TextButton", 56, 256, 288, 48, { text = "Buy 450", interactive = true })
		t:expect(rules(Rules.analyze(snapshot()))["hollow-plate"]):toBe(nil)
	end)

	harness:case("content on one side of a full-screen page is a lopsided page", function(t)
		local add, snapshot = scene()
		local root = add(nil, "Frame", 0, 0, 1920, 1080)
		add(root, "Frame", 0, 0, 1920, 1080, { opaque = true })
		local column = add(root, "Frame", 16, 100, 1100, 900)
		for row = 0, 4 do
			add(column, "TextLabel", 16, 100 + row * 120, 1100, 100, { text = "Part " .. row, size = 22 })
		end
		local counts = rules(Rules.analyze(snapshot()))
		t:expect(counts["lopsided-page"]):toBe(1)
	end)

	harness:case("HUD texts straight on the world are floating text; a plated group is not", function(t)
		local add, snapshot = scene()
		local hud = add(nil, "Frame", 0, 0, 1920, 1080)
		add(hud, "TextLabel", 16, 16, 200, 40, { text = "ION", size = 36 })
		add(hud, "TextLabel", 16, 60, 200, 20, { text = "Level 7", size = 16 })
		add(hud, "TextLabel", 16, 84, 200, 20, { text = "Pit zone", size = 16 })
		t:expect(rules(Rules.analyze(snapshot()))["floating-text"]):toBe(1)
		local add2, snapshot2 = scene()
		local plate = add2(nil, "Frame", 8, 8, 240, 110, { opaque = true, fill = PANEL })
		add2(plate, "TextLabel", 16, 16, 200, 40, { text = "ION", size = 36 })
		add2(plate, "TextLabel", 16, 60, 200, 20, { text = "Level 7", size = 16 })
		add2(plate, "TextLabel", 16, 84, 200, 20, { text = "Pit zone", size = 16 })
		t:expect(rules(Rules.analyze(snapshot2()))["floating-text"]):toBe(nil)
	end)

	harness:case(
		"two texts drawn over each other are overlapping text; a card of a fan that backs one is not",
		function(t)
			local add, snapshot = scene()
			local page = add(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
			add(
				page,
				"TextLabel",
				100,
				100,
				200,
				30,
				{ text = "Bank", ink = { x = 100, y = 100, width = 200, height = 30 } }
			)
			add(
				page,
				"TextLabel",
				150,
				110,
				200,
				30,
				{ text = "Stake", ink = { x = 150, y = 110, width = 200, height = 30 } }
			)
			local report = Rules.analyze(snapshot())
			t:expect(rules(report)["overlapping-text"]):toBe(1)
			t:expect(report.findings[1].severity):toBe("high")
			local add2, snapshot2 = scene()
			local page2 = add2(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
			local hand = add2(page2, "Frame", 100, 90, 400, 60, { fan = true })
			local first = add2(hand, "Frame", 100, 90, 220, 60, { opaque = true, fill = PANEL })
			add2(
				first,
				"TextLabel",
				100,
				100,
				200,
				30,
				{ text = "Ace", ink = { x = 100, y = 100, width = 200, height = 30 } }
			)
			local second = add2(hand, "Frame", 140, 90, 220, 60, { opaque = true, fill = PANEL })
			add2(
				second,
				"TextLabel",
				150,
				110,
				200,
				30,
				{ text = "King", ink = { x = 150, y = 110, width = 200, height = 30 } }
			)
			t:expect(rules(Rules.analyze(snapshot2()))["overlapping-text"]):toBe(nil)
			local add3, snapshot3 = scene()
			local page3 = add3(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
			add3(
				page3,
				"TextLabel",
				100,
				100,
				200,
				30,
				{ text = "Ready", ink = { x = 100, y = 100, width = 200, height = 30 } }
			)
			add3(
				page3,
				"TextLabel",
				100,
				100,
				200,
				30,
				{ text = "Ready", ink = { x = 100, y = 100, width = 200, height = 30 } }
			)
			t:expect(rules(Rules.analyze(snapshot3()))["overlapping-text"]):toBe(nil)
		end
	)

	harness:case("a text under a plate from another part is covered text", function(t)
		local function build(options: { fan: boolean?, z: number?, turn: number?, labels: number? })
			local add, snapshot = scene()
			local page = add(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
			local row = add(page, "Frame", 80, 90, 400, 200, { fan = options.fan })
			local group = add(row, "Frame", 100, 100, 200, 160, { z = options.z })
			for index = 1, options.labels or 1 do
				local y = 100 + (index - 1) * 50
				add(group, "TextLabel", 100, y, 200, 30, {
					text = "Total " .. index,
					ink = { x = 100, y = y, width = 200, height = 30 },
				})
			end
			add(row, "Frame", 80, 90, 400, 200, { opaque = true, fill = PANEL, turn = options.turn })
			return rules(Rules.analyze(snapshot()))
		end
		t:expect(build({})["covered-text"]):toBe(1)
		t:expect(build({ fan = true })["covered-text"]):toBe(nil)
		t:expect(build({ z = 2 })["covered-text"]):toBe(nil)
		t:expect(build({ turn = 30 })["covered-text"]):toBe(nil)
		t:expect(build({ labels = 3 })["covered-text"]):toBe(nil)
	end)

	harness:case("three native labels are native text", function(t)
		local function build(count: number)
			local add, snapshot = scene()
			local page = add(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
			for index = 1, count do
				add(page, "TextLabel", 40, 40 * index, 300, 24, { text = "Line " .. index, native = true })
			end
			return rules(Rules.analyze(snapshot()))
		end
		t:expect(build(3)["native-text"]):toBe(1)
		t:expect(build(2)["native-text"]):toBe(nil)
	end)

	harness:case("a ground image backs the texts that sit on it", function(t)
		local add, snapshot = scene()
		local hud = add(nil, "Frame", 0, 0, 1920, 1080)
		add(hud, "ImageLabel", 0, 0, 1920, 1080, { image = true })
		add(hud, "TextLabel", 16, 16, 200, 40, { text = "ION", size = 36 })
		add(hud, "TextLabel", 16, 60, 200, 20, { text = "Level 7", size = 16 })
		add(hud, "TextLabel", 16, 84, 200, 20, { text = "Pit zone", size = 16 })
		t:expect(rules(Rules.analyze(snapshot()))["floating-text"]):toBe(nil)
	end)

	harness:case("a text that runs past its plate or is cut by a clip is escaped text", function(t)
		local wide = { x = 120, y = 120, width = 220, height = 24 }
		local function build(options: {
			ink: Rules.ReviewRect?,
			clips: boolean?,
			class: string?,
			panel: boolean?,
			turn: number?,
		})
			local add, snapshot = scene()
			local page = add(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
			local holder = page
			if options.panel then
				holder = add(page, "Frame", 60, 60, 600, 300, { opaque = true, fill = PANEL })
			end
			local card = add(holder, options.class or "Frame", 100, 100, 200, 80, {
				opaque = not options.panel,
				image = options.panel,
				fill = PANEL,
				clips = options.clips,
			})
			add(card, "TextLabel", 120, 120, 160, 24, {
				text = "Secret word",
				size = 20,
				ink = options.ink or wide,
				turn = options.turn,
			})
			return Rules.analyze(snapshot())
		end
		local past = build({})
		t:expect(rules(past)["escaped-text"]):toBe(1)
		t:expect(string.find(past.text, "runs past the edge of", 1, true) ~= nil):toBe(true)
		t:expect(rules(build({ ink = { x = 120, y = 120, width = 160, height = 24 } }))["escaped-text"]):toBe(nil)
		local cut = build({ clips = true })
		t:expect(rules(cut)["escaped-text"]):toBe(1)
		t:expect(string.find(cut.text, "is cut by", 1, true) ~= nil):toBe(true)
		t:expect(rules(build({ clips = true, class = "ScrollingFrame" }))["escaped-text"]):toBe(nil)
		t:expect(rules(build({ panel = true }))["escaped-text"]):toBe(nil)
		t:expect(rules(build({ turn = 6 }))["escaped-text"]):toBe(nil)
	end)

	harness:case("escaped text counts an image only when it is built beside the text", function(t)
		local ink = { x = 120, y = 120, width = 220, height = 24 }
		local add, snapshot = scene()
		local page = add(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
		local note = add(page, "Frame", 100, 100, 200, 80)
		add(note, "ImageLabel", 100, 100, 200, 80, { image = true })
		local lines = add(note, "Frame", 100, 100, 200, 80)
		add(lines, "TextLabel", 120, 120, 160, 24, { text = "Guesses land here", size = 18, ink = ink })
		t:expect(rules(Rules.analyze(snapshot()))["escaped-text"]):toBe(1)
		local add2, snapshot2 = scene()
		local page2 = add2(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
		add2(page2, "ImageLabel", 100, 100, 200, 80, { image = true })
		local deep = page2
		for _ = 1, 4 do
			deep = add2(deep, "Frame", 100, 100, 300, 80)
		end
		add2(deep, "TextLabel", 120, 120, 160, 24, { text = "Guesses land here", size = 18, ink = ink })
		t:expect(rules(Rules.analyze(snapshot2()))["escaped-text"]):toBe(nil)
		local add3, snapshot3 = scene()
		local page3 = add3(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
		add3(page3, "TextButton", 100, 100, 120, 40, {
			opaque = true,
			fill = PANEL,
			interactive = true,
			text = "Deal again",
			size = 20,
			ink = { x = 80, y = 108, width = 160, height = 24 },
		})
		t:expect(rules(Rules.analyze(snapshot3()))["escaped-text"]):toBe(1)
	end)

	harness:case("an image covers a text only where its painted bounds reach", function(t)
		local function build(paint: Rules.ReviewRect?)
			local add, snapshot = scene()
			local page = add(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
			local row = add(page, "Frame", 200, 190, 1300, 700)
			local header = add(row, "Frame", 690, 198, 540, 54)
			add(header, "TextLabel", 690, 198, 540, 54, {
				text = "Choose your companion",
				size = 30,
				ink = { x = 814, y = 206, width = 292, height = 37 },
			})
			local choice = add(row, "Frame", 698, 195, 523, 687)
			add(choice, "ImageLabel", 698, 195, 523, 687, { image = true, paint = paint })
			return rules(Rules.analyze(snapshot()))
		end
		t:expect(build(nil)["covered-text"]):toBe(1)
		t:expect(build({ x = 730, y = 270, width = 459, height = 541 })["covered-text"]):toBe(nil)
		t:expect(build({ x = 730, y = 200, width = 459, height = 611 })["covered-text"]):toBe(1)
		t:expect(build({ x = 959, y = 538, width = 0, height = 0 })["covered-text"]):toBe(nil)
	end)

	harness:case("a text escapes an image at the edge of its painted bounds", function(t)
		local card = { x = 258, y = 18, width = 200, height = 62 }
		local cardPaint = { x = 267, y = 24, width = 184, height = 51 }
		local function build(ink: Rules.ReviewRect, paint: Rules.ReviewRect?)
			local add, snapshot = scene()
			local page = add(nil, "Frame", 0, 0, 749, 389, { opaque = true })
			local word = add(page, "Frame", card.x, card.y, card.width, card.height)
			add(word, "ImageLabel", card.x, card.y, card.width, card.height, { image = true, paint = paint })
			local lines = add(word, "Frame", card.x, card.y, card.width, card.height)
			add(
				lines,
				"TextLabel",
				ink.x,
				ink.y,
				ink.width,
				ink.height,
				{ text = "YOUR SECRET WORD", size = 14, ink = ink }
			)
			local taken = snapshot()
			taken.width, taken.height = 749, 389
			return Rules.analyze(taken)
		end
		local overTopEdge = { x = 302, y = 20, width = 113, height = 14 }
		t:expect(rules(build(overTopEdge, nil))["escaped-text"]):toBe(nil)
		local escaped = build(overTopEdge, cardPaint)
		t:expect(rules(escaped)["escaped-text"]):toBe(1)
		t:expect(string.find(escaped.text, "runs past the edge of", 1, true) ~= nil):toBe(true)
		local onThePaint = { x = 302, y = 30, width = 113, height = 14 }
		t:expect(rules(build(onThePaint, cardPaint))["escaped-text"]):toBe(nil)
		local cornerOfMargin = { x = 260, y = 19, width = 14, height = 12 }
		t:expect(rules(build(cornerOfMargin, cardPaint))["escaped-text"]):toBe(nil)
		local pastTheRectangle = { x = 250, y = 19, width = 40, height = 14 }
		t:expect(rules(build(pastTheRectangle, cardPaint))["escaped-text"]):toBe(1)
		t:expect(rules(build(pastTheRectangle, nil))["escaped-text"]):toBe(1)
	end)

	harness:case("a text of a stack escapes the paint of the ground of that stack at any share", function(t)
		local paint = { x = 108, y = 108, width = 134, height = 74 }
		local function build(ink: Rules.ReviewRect, ground: boolean, nested: boolean)
			local add, snapshot = scene()
			local page = add(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
			local card = add(page, "Frame", 100, 100, 150, 90)
			add(card, "ImageLabel", 100, 100, 150, 90, { image = true, paint = paint, ground = ground, z = 0 })
			local holder = card
			if nested then
				holder = add(card, "Frame", 108, 108, 134, 30, { opaque = true, fill = PANEL })
			end
			add(
				holder,
				"TextLabel",
				108,
				108,
				134,
				24,
				{ text = "A label that is far too long for this card", size = 24, ink = ink }
			)
			return rules(Rules.analyze(snapshot()))
		end
		local farPast = { x = 108, y = 108, width = 352, height = 24 }
		t:expect(build(farPast, false, false)["escaped-text"]):toBe(nil)
		t:expect(build(farPast, true, false)["escaped-text"]):toBe(1)
		local inside = { x = 110, y = 110, width = 120, height = 24 }
		t:expect(build(inside, true, false)["escaped-text"]):toBe(nil)
		local onTheMargin = { x = 101, y = 101, width = 30, height = 12 }
		t:expect(build(onTheMargin, false, false)["escaped-text"]):toBe(nil)
		t:expect(build(onTheMargin, true, false)["escaped-text"]):toBe(1)
		t:expect(build(inside, true, true)["escaped-text"]):toBe(nil)
	end)

	harness:case("a text on the paint of an image is not floating text", function(t)
		local function build(paint: Rules.ReviewRect?, above: boolean)
			local add, snapshot = scene()
			local hud = add(nil, "Frame", 0, 0, 1920, 1080)
			for row = 0, 2 do
				local y = 16 + row * 100
				local card = add(hud, "Frame", 16, y, 240, 80)
				add(card, "ImageLabel", 16, y, 240, 80, {
					image = true,
					paint = if paint ~= nil
						then { x = paint.x, y = y + paint.y, width = paint.width, height = paint.height }
						else nil,
					z = if above then 3 else 0,
				})
				add(card, "TextLabel", 32, y + 24, 200, 32, { text = "Quest " .. row, size = 24 })
			end
			return rules(Rules.analyze(snapshot()))
		end
		t:expect(build(nil, false)["floating-text"]):toBe(nil)
		t:expect(build({ x = 20, y = 4, width = 232, height = 72 }, false)["floating-text"]):toBe(nil)
		t:expect(build({ x = 20, y = 60, width = 232, height = 16 }, false)["floating-text"]):toBe(1)
		t:expect(build(nil, true)["floating-text"]):toBe(1)
	end)

	harness:case("an image separates two overlapping texts only where it is painted", function(t)
		local function build(paint: Rules.ReviewRect?)
			local add, snapshot = scene()
			local page = add(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
			add(page, "TextLabel", 100, 100, 200, 30, {
				text = "Pot",
				ink = { x = 100, y = 100, width = 200, height = 30 },
			})
			local card = add(page, "Frame", 80, 80, 400, 200)
			add(card, "ImageLabel", 80, 80, 400, 200, { image = true, paint = paint })
			add(card, "TextLabel", 150, 110, 200, 30, {
				text = "Stake",
				ink = { x = 150, y = 110, width = 200, height = 30 },
			})
			return rules(Rules.analyze(snapshot()))
		end
		t:expect(build(nil)["overlapping-text"]):toBe(nil)
		t:expect(build({ x = 90, y = 90, width = 380, height = 180 })["overlapping-text"]):toBe(nil)
		t:expect(build({ x = 320, y = 90, width = 150, height = 180 })["overlapping-text"]):toBe(1)
	end)

	harness:case("painted bounds come from the opaque pixels and follow the scale mode", function(t)
		local Paint = require("../src/ui/paint_bounds")
		local width, height = 200, 100
		local pixels = buffer.create(width * height * 4)
		local function fill(x0: number, y0: number, x1: number, y1: number, alpha: number)
			for y = y0, y1 - 1 do
				for x = x0, x1 - 1 do
					buffer.writeu8(pixels, (y * width + x) * 4 + 3, alpha)
				end
			end
		end
		fill(20, 10, 160, 60, 255)
		fill(20, 60, 160, 80, 140)
		fill(20, 80, 180, 95, 20)
		local box = Paint.measure(pixels, width, height)
		t:expect(box):toEqual({ x0 = 20, y0 = 10, x1 = 160, y1 = 80, width = 200, height = 100 })
		local empty = Paint.measure(buffer.create(16 * 4), 4, 4)
		t:expect(empty.x1 - empty.x0):toBe(0)
		local rect = { x = 100, y = 50, width = 400, height = 100 }
		t:expect(Paint.place(rect, box, "Stretch", nil, 0)):toEqual({ x = 140, y = 60, width = 280, height = 70 })
		t:expect(Paint.place(rect, box, "Fit", nil, 0)):toEqual({ x = 220, y = 60, width = 140, height = 70 })
		t:expect(Paint.place(rect, box, "Crop", nil, 0)):toEqual({ x = 140, y = 50, width = 280, height = 100 })
		t:expect(Paint.place(rect, box, "Tile", nil, 0)):toEqual(rect)
		t:expect(Paint.place(rect, empty, "Stretch", nil, 0).width):toBe(0)
		local slice = { x0 = 50, y0 = 30, x1 = 150, y1 = 70, scale = 1 }
		t:expect(Paint.place(rect, box, "Slice", slice, 0)):toEqual({ x = 120, y = 60, width = 340, height = 70 })
		local upright = { x = 100, y = 50, width = 200, height = 100 }
		t:expect(Paint.place(upright, box, "Stretch", nil, 1)):toEqual({ x = 170, y = 20, width = 70, height = 140 })
		t:expect(Paint.place(upright, box, "Stretch", nil, 2)):toEqual({ x = 140, y = 70, width = 140, height = 70 })
		t:expect(Paint.place(upright, box, "Stretch", nil, 3)):toEqual({ x = 160, y = 40, width = 70, height = 140 })
		t:expect(Paint.place(upright, box, "Stretch", nil, -1)):toEqual(Paint.place(upright, box, "Stretch", nil, 3))
	end)

	harness:case("a screen-size image stays out of the cover and backing checks whatever its paint", function(t)
		local banner = { x = 600, y = 270, width = 700, height = 400 }
		local function overlay(paint: Rules.ReviewRect?)
			local add, snapshot = scene()
			local page = add(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
			local hud = add(page, "Frame", 0, 0, 1920, 1080)
			add(hud, "TextLabel", 700, 300, 300, 40, {
				text = "Lap 2 of 3",
				size = 28,
				ink = { x = 700, y = 300, width = 160, height = 34 },
			})
			local layer = add(page, "Frame", 0, 0, 1920, 1080)
			add(layer, "ImageLabel", 0, 0, 1920, 1080, { image = true, paint = paint })
			return rules(Rules.analyze(snapshot()))
		end
		t:expect(overlay(nil)["covered-text"]):toBe(nil)
		t:expect(overlay(banner)["covered-text"]):toBe(nil)
		local function button(paint: Rules.ReviewRect?)
			local add, snapshot = scene()
			local page = add(nil, "Frame", 0, 0, 1920, 1080)
			add(page, "ImageLabel", 0, 0, 1920, 1080, { image = true, paint = paint })
			add(page, "TextButton", 800, 400, 120, 40, {
				opaque = true,
				fill = PANEL,
				interactive = true,
				text = "Deal again",
				size = 20,
				ink = { x = 790, y = 405, width = 160, height = 28 },
			})
			return rules(Rules.analyze(snapshot()))
		end
		t:expect(button(nil)["escaped-text"]):toBe(1)
		t:expect(button(banner)["escaped-text"]):toBe(1)
	end)

	harness:case("collect takes painted bounds from paintRect, then from the pixels in Studio", function(t)
		type Fake = { [string]: unknown }
		local reads = 0
		local function vector(x: number, y: number): Fake
			return { X = x, Y = y }
		end
		local function editable(
			width: number,
			height: number,
			left: number,
			top: number,
			right: number,
			bottom: number
		): Fake
			return {
				Size = vector(width, height),
				ReadPixelsBuffer = function(_: Fake, position: Fake, size: Fake): buffer
					local fromX, fromY = position.X :: number, position.Y :: number
					local wide, tall = size.X :: number, size.Y :: number
					local pixels = buffer.create(wide * tall * 4)
					for y = 0, tall - 1 do
						for x = 0, wide - 1 do
							local sourceX, sourceY = fromX + x, fromY + y
							if sourceX >= left and sourceX < right and sourceY >= top and sourceY < bottom then
								buffer.writeu8(pixels, (y * wide + x) * 4 + 3, 255)
							end
						end
					end
					return pixels
				end,
				Destroy = function() end,
			}
		end
		local function world(studio: boolean): Fake
			local services: { [string]: Fake } = {
				Workspace = { CurrentCamera = { ViewportSize = vector(749, 389) } },
				RunService = {
					IsStudio = function(): boolean
						return studio
					end,
				},
				AssetService = {
					CreateEditableImageAsync = function(_: Fake, content: unknown): Fake
						reads += 1
						assert(content ~= "locked", "no permission to load asset")
						return editable(392, 182, 16, 16, 376, 166)
					end,
				},
			}
			return {
				GetService = function(_: Fake, name: string): Fake?
					return services[name]
				end,
			}
		end
		local function node(class: string, name: string, properties: Fake, kids: { Fake }?): Fake
			local made: Fake = table.clone(properties)
			made.ClassName, made.Name = class, name
			made.IsA = function(_: Fake, asked: string): boolean
				return asked == class or (asked == "GuiObject" and class ~= "ScreenGui")
			end
			made.GetChildren = function(): { Fake }
				return kids or {}
			end
			made.GetFullName = function(): string
				return "Gui." .. name
			end
			return made
		end
		local function image(name: string, uri: string, attributes: Fake?, crop: { Fake }?): Fake
			return node("ImageLabel", name, {
				AbsolutePosition = vector(258, 18),
				AbsoluteSize = vector(200, 62),
				Image = uri,
				ImageContent = if uri == "rbxassetid://locked" then "locked" else uri,
				ImageRectOffset = if crop then crop[1] else vector(0, 0),
				ImageRectSize = if crop then crop[2] else vector(0, 0),
				ScaleType = { Name = "Stretch" },
				GetAttribute = function(_: Fake, key: string): unknown
					return if attributes then attributes[key] else nil
				end,
			})
		end
		local function paintOf(game: Fake, child: Fake): Rules.ReviewRect?
			local screen = node("ScreenGui", "Screen", {
				FindFirstAncestorWhichIsA = function(): Fake
					return game
				end,
			}, { child })
			screen.IsA = function(_: Fake, asked: string): boolean
				return asked == "ScreenGui" or asked == "LayerCollector"
			end
			local review = require("../src/ui/review")
			local snapshot = review.collect({ root = (screen :: unknown) :: Instance })
			return snapshot.elements[1].paint
		end
		local studio = world(true)
		local measured = paintOf(studio, image("Card", "rbxassetid://card"))
		t:expect(measured ~= nil):toBe(true)
		local paint = measured :: Rules.ReviewRect
		t:expect(math.abs(paint.x - (258 + 16 * 200 / 392)) < 0.01):toBe(true)
		t:expect(math.abs(paint.y - (18 + 16 * 62 / 182)) < 0.01):toBe(true)
		t:expect(math.abs(paint.width - 360 * 200 / 392) < 0.01):toBe(true)
		t:expect(math.abs(paint.height - 150 * 62 / 182) < 0.01):toBe(true)
		t:expect(reads):toBe(1)
		paintOf(studio, image("CardAgain", "rbxassetid://card"))
		t:expect(reads):toBe(1)
		t:expect(paintOf(studio, image("Locked", "rbxassetid://locked"))):toBe(nil)
		t:expect(paintOf(world(false), image("Live", "rbxassetid://live"))):toBe(nil)
		local declared = paintOf(
			world(false),
			image("Declared", "rbxassetid://locked", {
				FacetPaintRect = { Min = vector(98, 0), Max = vector(294, 182) },
				FacetSourceSize = vector(392, 182),
			})
		)
		t:expect(declared):toEqual({ x = 308, y = 18, width = 100, height = 62 })
		local declaredInStudio = paintOf(
			studio,
			image("DeclaredCard", "rbxassetid://card", {
				FacetPaintRect = { Min = vector(98, 0), Max = vector(294, 182) },
				FacetSourceSize = vector(392, 182),
			})
		)
		t:expect(declaredInStudio):toEqual(declared)
		local cropped =
			paintOf(studio, image("Cropped", "rbxassetid://sheet", nil, { vector(196, 91), vector(196, 91) }))
		t:expect(cropped ~= nil):toBe(true)
		local part = cropped :: Rules.ReviewRect
		t:expect(math.abs(part.x - 258) < 0.01):toBe(true)
		t:expect(math.abs(part.width - 180 * 200 / 196) < 0.01):toBe(true)
		t:expect(math.abs(part.y - 18) < 0.01):toBe(true)
		t:expect(math.abs(part.height - 75 * 62 / 91) < 0.01):toBe(true)
	end)

	harness:case("a HUD control over the Jump button on touch is reported", function(t)
		local add, snapshot = scene()
		add(nil, "TextButton", 1600, 880, 300, 80, { text = "Enter race", interactive = true })
		local touched = snapshot()
		touched.touch = true
		t:expect(rules(Rules.analyze(touched))["touch-control-overlap"]):toBe(1)
		t:expect(rules(Rules.analyze(snapshot()))["touch-control-overlap"]):toBe(nil)
	end)

	harness:case("a Composition that does not fit a phone is reported with its regions", function(t)
		local add, snapshot = scene()
		local hub = add(nil, "Frame", 0, 0, 1920, 1080)
		local fitting = snapshot()
		t:expect(rules(Rules.analyze(fitting))["composition-unfit"]):toBe(nil)
		local unfit = snapshot()
		unfit.elements[hub].unfit = "358 by 812: Destinations, Race"
		local report = Rules.analyze(unfit)
		t:expect(rules(report)["composition-unfit"]):toBe(1)
		t:expect(string.find(report.text, "Destinations, Race", 1, true) ~= nil):toBe(true)
	end)

	harness:case("controls taller than their scroll area are one oversized target for each area", function(t)
		local add, snapshot = scene()
		local page = add(nil, "Frame", 0, 0, 749, 389)
		local list = add(page, "ScrollingFrame", 16, 148, 713, 167, { clips = true })
		add(list, "TextButton", 16, 148, 348, 290, { text = "Kart 1", interactive = true })
		add(list, "TextButton", 380, 148, 348, 290, { text = "Kart 2", interactive = true })
		local report = Rules.analyze(snapshot())
		local detail = "2 control(s) up to 290 px tall in a scroll area 167 px tall"
		t:expect(rules(report)["oversized-target"]):toBe(1)
		t:expect(string.find(report.text, "medium rule(s): each one names", 1, true) ~= nil):toBe(true)
		t:expect(string.find(report.text, detail, 1, true) ~= nil):toBe(true)
		t:expect(report.fixes["oversized-target"] ~= nil):toBe(true)
	end)

	harness:case("a control that fits its scroll area, or has none, is not an oversized target", function(t)
		local add, snapshot = scene()
		local page = add(nil, "Frame", 0, 0, 749, 389)
		local list = add(page, "ScrollingFrame", 16, 148, 713, 167, { clips = true })
		add(list, "TextButton", 16, 148, 348, 150, { text = "Kart 1", interactive = true })
		add(list, "TextButton", 16, 640, 348, 150, { text = "Kart 9", interactive = true })
		add(page, "TextButton", 16, 16, 348, 600, { text = "Poster", interactive = true })
		add(list, "TextButton", 16, 148, 348, 290, { text = "Hidden", interactive = true, visible = false })
		t:expect(rules(Rules.analyze(snapshot()))["oversized-target"]):toBe(nil)
	end)

	harness:case("a subject image counts toward the used area of a surface", function(t)
		local add, snapshot = scene()
		local page = add(nil, "Frame", 0, 0, 1920, 1080, { opaque = true })
		add(page, "TextLabel", 40, 40, 300, 30, { text = "Pulse", size = 40, bold = true })
		add(page, "TextLabel", 40, 90, 300, 20, { text = "Grip", size = 16 })
		add(page, "ViewportFrame", 500, 100, 1300, 900, { image = true })
		t:expect(rules(Rules.analyze(snapshot()))["stranded-content"]):toBe(nil)
	end)

	harness:case("a parent cycle does not stop the analysis", function(t)
		local add, snapshot = scene()
		add(2, "Frame", 0, 0, 400, 400, { opaque = true })
		add(1, "TextLabel", 0, 0, 400, 20, { text = "Coins · 40" })
		t:expect(#Rules.analyze(snapshot()).findings >= 1):toBe(true)
	end)

	harness:case("a malformed snapshot is refused", function(t)
		local ok = pcall(function()
			Rules.analyze((({}) :: unknown) :: Rules.ReviewSnapshot)
		end)
		t:expect(ok):toBe(false)
	end)

	harness:case("collect reads styled text, role tags, fills and effective visibility from instances", function(t)
		local engineLib = require("./lib/native_engine")
		local Facet = require("../src")
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, { types = engine.types })
		local screen = engine.new("ScreenGui")
		local stop = runtime.mount(function()
			return UI.VStack "Card" {
				UI.Text "Value" { text = "1000", textRole = "numeral" },
				UI.Text "Label" { text = "Wins 0 · Losses 0", textRole = "caption" },
				UI.Text "Hidden" { text = "Hidden 0 · 0", Visible = false },
			}
		end, screen)
		local V2 = engine.types.Vector2
		local card = assert(screen:FindFirstChild("Card", true))
		for _, name in { "Value", "Label", "Hidden" } do
			local node = card:FindFirstChild(name)
			assert(node)
			engine.environment.poke(node, "AbsolutePosition", V2.new(10, 10))
			engine.environment.poke(node, "AbsoluteSize", V2.new(200, 40))
		end
		engine.environment.poke(card, "AbsolutePosition", V2.new(10, 10))
		engine.environment.poke(card, "AbsoluteSize", V2.new(200, 40))
		local review = require("../src/ui/review")
		local snapshot = review.collect({ root = screen })
		local byName: { [string]: Rules.ReviewElement } = {}
		for _, element in snapshot.elements do
			byName[string.match(element.path, "([^%.]+)$") or element.path] = element
		end
		t:expect(byName.Value ~= nil):toBe(true)
		t:expect((byName.Value.text :: Rules.ReviewText).content):toBe("1000")
		t:expect((byName.Value.text :: Rules.ReviewText).role):toBe("numeral")
		t:expect((byName.Label.text :: Rules.ReviewText).role):toBe("caption")
		t:expect(byName.Hidden.visible):toBe(false)
		t:expect(byName.Value.parent):toBe(byName.Card.index)
		local report = review.analyze(snapshot)
		local joined = 0
		for _, finding in report.findings do
			if finding.rule == "joined-facts" then
				joined += 1
			end
		end
		t:expect(joined):toBe(1)
		stop()
		runtime:dispose()
	end)

	harness:case("collect counts the art of a skin as built in the part that wears the skin", function(t)
		local engineLib = require("./lib/native_engine")
		local engine = engineLib.new()
		local V2 = engine.types.Vector2
		local screen = engine.new("ScreenGui")
		local function part(class: string, name: string, parent: Instance): Instance
			local node = engine.new(class)
			node.Name = name
			node.Parent = parent
			engine.environment.poke(node, "AbsolutePosition", V2.new(0, 0))
			engine.environment.poke(node, "AbsoluteSize", V2.new(749, 331))
			return node
		end
		local panel = part("Frame", "Panel", screen)
		panel:AddTag("facet-skinned")
		local boundary = part("Frame", "SkinBoundary", part("CanvasGroup", "Fade", panel))
		local art = part("ImageLabel", "Art", part("Frame", "Skin", part("Frame", "SkinBounds", boundary)))
		local artImage = (art :: unknown) :: ImageLabel
		artImage.Image = "rbxassetid://1"
		art:AddTag("facet-skin-art")
		local loose = part("ImageLabel", "Loose", part("Frame", "Holder", part("Frame", "Plain", screen)))
		local looseImage = (loose :: unknown) :: ImageLabel
		looseImage.Image = "rbxassetid://1"
		loose:AddTag("facet-skin-art")
		local review = require("../src/ui/review")
		local snapshot = review.collect({ root = screen })
		local byName: { [string]: Rules.ReviewElement } = {}
		for _, element in snapshot.elements do
			byName[string.match(element.path, "([^%.]+)$") or element.path] = element
		end
		t:expect(byName.Art.parent):toBe(byName.Panel.index)
		t:expect(byName.Loose.parent):toBe(byName.Holder.index)
	end)
end
