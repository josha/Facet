--!strict
local Verify = require("../tools/vendor/verify/src/core")
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
		t:expect(rows(false, false)["record-without-visual"]):toBe(1)
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
		local flat, flatReport = themes.define({ identity = { id = "flat" } })
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

	harness:case("a malformed snapshot is refused", function(t)
		local ok = pcall(function()
			Rules.analyze((({}) :: unknown) :: Rules.ReviewSnapshot)
		end)
		t:expect(ok):toBe(false)
	end)

	harness:case("collect reads styled text, role tags, fills and effective visibility from instances", function(t)
		local engineLib = require("./lib/native_engine")
		local Facet = require("../src")
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, { types = engine.types } :: any)
		local screen = engine.new("ScreenGui")
		local root: any
		local stop = runtime.mount(function()
			root = UI.VStack "Card" {
				UI.Text "Value" { text = "1000", textRole = "numeral" },
				UI.Text "Label" { text = "Wins 0 · Losses 0", textRole = "caption" },
				UI.Text "Hidden" { text = "Hidden 0 · 0", Visible = false },
			}
			return root
		end, screen)
		local V2 = engine.types.Vector2
		for _, node in
			{ root, root:FindFirstChild("Value"), root:FindFirstChild("Label"), root:FindFirstChild("Hidden") }
		do
			engine.environment.poke(node, "AbsolutePosition", V2.new(10, 10))
			engine.environment.poke(node, "AbsoluteSize", V2.new(200, 40))
		end
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
