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
		}
		if given.text ~= nil then
			element.text = {
				content = given.text,
				size = given.size or 18,
				bold = given.bold == true,
				font = given.font or "BuilderSans",
				color = WHITE,
				transparency = 0,
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
end
