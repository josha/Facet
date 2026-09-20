--!strict
-- The layout primitives adapt on their default path, and say so when content
-- does not fit. Each case runs at the six screen-size and input combos below.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src")
local world = require("./lib/world")

local FILL = { type = "fill", weight = 1 }
local FIXED = function(px: number)
	return { type = "fixed", px = px }
end

type Combo = { name: string, w: number, h: number, display: string? }
local COMBOS: { Combo } = {
	{ name = "compact touch portrait", w = 390, h = 844, display = "Small" },
	{ name = "compact touch landscape", w = 844, h = 390, display = "Small" },
	{ name = "regular touch tablet", w = 1024, h = 768, display = "Small" },
	{ name = "desktop pointer", w = 1600, h = 900, display = "Medium" },
	{ name = "ten-foot gamepad", w = 1920, h = 1080, display = "Large" },
	{ name = "hybrid pointer+touch", w = 1280, h = 800, display = "Medium" },
}

-- `build(UI, w)` returns the screen's root node. Answers the adapter, the
-- renderer controller and the world.
local function render(build: (any, any) -> any, combo: Combo, policy: string?): (any, any, any)
	local w = world.new({
		viewport = { x = 0, y = 0, w = combo.w, h = combo.h },
		safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
		displaySize = combo.display,
		overflowGuardOff = "these fixtures overflow their boxes to read the solver's findings",
	})
	w.present(function()
		return build(w.UI, w)
	end, { rootPolicy = policy or "edgeToEdge" })
	return w.adapter, w.controller, w
end

local function width(px: number): Combo
	return { name = `{px}px`, w = px, h = 800 }
end

-- The lane count the grid laid out, read off the rects: how many cells share the
-- first cell's row.
local function laneCount(adapter: any, prefix: string, n: number): number
	local first = adapter.node(prefix .. "1")
	if first == nil then
		return 0
	end
	local lanes = 0
	for i = 1, n do
		local node = adapter.node(prefix .. i)
		if node ~= nil and node.rect.y == first.rect.y then
			lanes += 1
		end
	end
	return lanes
end

-- `n` fixed boxes named `prefix1..n`, appended to `props` as its children.
local function withBoxes(UI: any, props: any, prefix: string, n: number, w: any, h: any): any
	for i = 1, n do
		table.insert(props, UI.Box(prefix .. i)({ width = w, height = h }))
	end
	return props
end

local function grid(props: any, n: number, w: number, h: number)
	return function(UI: any)
		return UI.Screen("S")({ UI.Grid("G")(withBoxes(UI, table.clone(props), "C", n, FIXED(w), FIXED(h))) })
	end
end

local function findings(controller: any, phrase: string?): { string }
	local out: { string } = {}
	for _, d in controller.diagnostics() do
		if phrase == nil or string.find(d.issue, phrase, 1, true) ~= nil then
			table.insert(out, d.issue)
		end
	end
	return out
end

local function missingPhrases(message: string, phrases: { string }): string
	local missing: { string } = {}
	for _, phrase in phrases do
		if string.find(message, phrase, 1, true) == nil then
			table.insert(missing, phrase)
		end
	end
	return `missing:{table.concat(missing, ",")}`
end

-- An undeclared Grid takes the widest child's measured extent as its lane
-- minimum and divides the offered box through `adaptive.columnsFor`, the same
-- function the declared route calls, so the ten-foot cap applies.
describe("ADAPT-L2 — Grid lanes itself from the space it got", function()
	-- six 160px cards with `minColumnWidth = 160` declared, per combo
	local EXPECTED = { 2, 4, 6, 9, 5, 7 }

	for index, combo in COMBOS do
		it(`an undeclared Grid takes the offer's lanes at {combo.name}`, function()
			local adapter = render(grid({ gap = 12 }, 14, 160, 100), combo)
			expect(laneCount(adapter, "/S/G/C", 14)).toBe(EXPECTED[index])
		end)
	end

	it("the undeclared answer IS the declared answer, at every combo", function()
		for _, combo in COMBOS do
			local declared = render(grid({ gap = 12, minColumnWidth = 160 }, 14, 160, 100), combo)
			local defaulted = render(grid({ gap = 12 }, 14, 160, 100), combo)
			expect(laneCount(defaulted, "/S/G/C", 14)).toBe(laneCount(declared, "/S/G/C", 14))
		end
	end)

	it("a television gets FEWER lanes than a desktop, with nothing declared", function()
		local function lanes(combo: Combo): number
			return laneCount(render(grid({ gap = 12 }, 14, 160, 100), combo), "/S/G/C", 14)
		end
		expect(lanes(COMBOS[5])).toBeLessThan(lanes(COMBOS[4]))
	end)

	it("AUTHORED ALWAYS WINS: a declared lane count is untouched by the default", function()
		for _, combo in COMBOS do
			expect(laneCount(render(grid({ gap = 12, columns = 3 }, 9, 160, 100), combo), "/S/G/C", 9)).toBe(3)
		end
	end)

	it("...and so is a declared minimum, in both directions", function()
		-- a minimum wider than the children wins: two lanes on a 1600 desktop
		local wide = render(grid({ gap = 12, minColumnWidth = 700 }, 6, 160, 100), COMBOS[4])
		expect(laneCount(wide, "/S/G/C", 6)).toBe(2)
		-- ...and one narrower than them wins too: six lanes, one per child
		local narrow = render(grid({ gap = 12, minColumnWidth = 40 }, 6, 160, 100), COMBOS[4])
		expect(laneCount(narrow, "/S/G/C", 6)).toBe(6)
	end)

	it("THE NULL HYPOTHESIS: a grid of fill children still gets one lane", function()
		-- a `fill` child has no intrinsic minimum, so the one-lane fallback stands
		local adapter = render(function(UI)
			return UI.Screen("S")({ UI.Grid("G")(withBoxes(UI, { gap = 12 }, "C", 6, FILL, FIXED(40))) })
		end, COMBOS[4])
		expect(laneCount(adapter, "/S/G/C", 6)).toBe(1)
	end)
end)

-- `AdaptiveStack.axis` is required. The refusal names the reactive fact for a
-- stack that adapts and `UI.VStack` for an author who wants a column.
describe("ADAPT-L4 — AdaptiveStack refuses rather than silently not adapting", function()
	local function bare(UI: any)
		return UI.Screen("S")({ UI.AdaptiveStack("Panels")({ gap = 8, UI.Box("A")({}) }) })
	end

	it("a bare AdaptiveStack REFUSES to construct", function()
		expect(function()
			render(bare, COMBOS[1])
		end).toThrow()
	end)

	it("...and the refusal names the host, the fact, and the unconditional class", function()
		local ok, err = pcall(render, bare, COMBOS[1])
		expect(ok).toBe(false)
		expect(
			missingPhrases(
				tostring(err),
				{ "AdaptiveStack.axis is required", "adaptive.conditions", "client.host.new", "UI.VStack" }
			)
		).toBe("missing:")
	end)

	it("THE NULL HYPOTHESIS: a bound axis constructs and still flips in place", function()
		local adapter, _, w = render(function(UI, w)
			return UI.Screen("S")({
				UI.AdaptiveStack("Bar")({
					axis = Facet.adaptive.conditions(w.env).axis,
					gap = 8,
					UI.Box("A")({ width = FIXED(60), height = FIXED(20) }),
					UI.Box("B")({ width = FIXED(60), height = FIXED(20) }),
				}),
			})
		end, { name = "narrow", w = 400, h = 800 })
		local node = adapter.node("/S/Bar/B")
		local column = node.rect
		w.env:set("viewportRect", { x = 0, y = 0, w = 900, h = 800 })
		w.settle()
		local row = adapter.node("/S/Bar/B").rect
		-- a column puts B under A; a row puts it beside it, on the same node
		expect(`{column.x},{column.y} -> {row.x},{row.y}`).toBe("0,28 -> 68,0")
		expect(adapter.node("/S/Bar/B")).toBe(node)
	end)

	it("two 132px plates are a column at 320px and a row at 1280px", function()
		local adapter, _, w = render(function(UI, w)
			return UI.Screen("S")({
				UI.AdaptiveStack("Panels")({
					axis = Facet.adaptive.conditions(w.env).axis,
					gap = 8,
					width = FILL,
					UI.Box("One")({ width = FIXED(132), height = FIXED(60) }),
					UI.Box("Many")({ width = FIXED(132), height = FIXED(60) }),
				}),
			})
		end, { name = "320", w = 320, h = 640 })
		expect(adapter.node("/S/Panels/Many").rect.y).toBe(68)
		w.env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 800 })
		w.settle()
		expect(adapter.node("/S/Panels/Many").rect.y).toBe(0)
	end)
end)

-- `conditions.axis` reads the raw window width, so a stack inside a padded
-- screen can be told "row" for space it does not have. The band where that
-- happens is reported by the solver.
describe("ADAPT-L3 — the axis is the SCREEN's width, and the solver says so", function()
	local function padded(px: number): (any, any, any)
		return render(function(UI, w)
			return UI.Screen("S")({
				padding = "l",
				UI.AdaptiveStack("Bar")(withBoxes(UI, {
					axis = Facet.adaptive.conditions(w.env).axis,
					gap = 8,
					width = FILL,
				}, "K", 3, FIXED(200), FIXED(44))),
			})
		end, width(px))
	end

	local function overflowFinding(controller: any): string?
		return findings(controller, "content overflows this")[1]
	end

	it("the band exists and is exactly the offer's, not the window's", function()
		-- 560: the window is under the threshold, so it is a column and fits
		local _, below = padded(560)
		expect(overflowFinding(below)).toBeNil()
		-- 600..640: the window says "row", the padded offer cannot hold one
		for _, px in { 600, 610, 640 } do
			local _, inside = padded(px)
			expect(overflowFinding(inside) ~= nil).toBe(true)
		end
		local _, above = padded(680)
		expect(overflowFinding(above)).toBeNil()
	end)

	it("...and it is NOT silent — the finding names the container, the amount and both fixes", function()
		local _, controller = padded(610)
		local issue = overflowFinding(controller) :: string
		expect(missingPhrases(issue, { "hstack", "54px", "paint outside its box", "ScrollView", "give it room" })).toBe(
			"missing:"
		)
	end)

	it("the fact itself is honest about what it is: `viewportWidth` IS the raw window", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 1920, h = 1080 }, displaySize = "Large" })
		local viewportWidth, contentWidth = w.scoped(function()
			local conditions = Facet.adaptive.conditions(w.env)
			return conditions.viewportWidth:peek(), conditions.contentWidth:peek()
		end)
		expect(viewportWidth).toBe(1920)
		expect(contentWidth).toBe(1920)
	end)
end)

-- A GridRow that squeezes its declared column widths files a named finding, the
-- same way an HStack does at the same width.
describe("ADAPT-L8 — a row grid says when it squeezed its columns", function()
	local function rowGrid(px: number): (any, any)
		return render(function(UI)
			local row = {}
			for i = 1, 3 do
				row[i] = UI.Text("C" .. i)({ text = "Cell " .. i, width = FIXED(200), height = FIXED(24) })
			end
			return UI.Screen("S")({ UI.Grid("G")({ gap = 8, width = FILL, UI.GridRow("Row")(row) }) })
		end, width(px))
	end

	local function squeezeFinding(controller: any): string?
		return findings(controller, "squeeze")[1]
	end

	it("a squeeze is REPORTED, at every width the audit measured one", function()
		for _, px in { 1024, 700 } do
			local adapter, controller = rowGrid(px)
			expect(adapter.node("/S/G/Row/C1").rect.w).toBe(200)
			expect(squeezeFinding(controller)).toBeNil()
		end
		for _, px in { 560, 460, 390, 320 } do
			local adapter, controller = rowGrid(px)
			expect(adapter.node("/S/G/Row/C1").rect.w).toBeLessThan(200)
			expect(squeezeFinding(controller) ~= nil).toBe(true)
		end
	end)

	it("...and the finding names the amount, the room, and the three ways out", function()
		local _, controller = rowGrid(320)
		local issue = squeezeFinding(controller) :: string
		expect(missingPhrases(issue, { "600px", "304px", "ScrollView", "give the grid room", "fewer columns" })).toBe(
			"missing:"
		)
	end)

	it("THE GEOMETRY DID NOT MOVE: the squeeze is still the squeeze", function()
		local widths: { number } = {}
		for _, px in { 1024, 560, 460, 390, 320 } do
			local adapter = rowGrid(px)
			table.insert(widths, adapter.node("/S/G/Row/C1").rect.w)
		end
		expect(table.concat(widths, ",")).toBe("200,181,148,124,101")
	end)
end)

-- Content that does not fit paints outside its box, nothing clips it, and the
-- solver files a complete finding at every combo.
describe("ADAPT-L5 — overflow is not silent, and says the same thing at every combo", function()
	local function tallPage(UI: any): any
		return UI.Screen("S")({ UI.VStack("Col")(withBoxes(UI, { width = FILL }, "R", 20, FILL, FIXED(80))) })
	end

	-- four 160px boxes in a row
	local function fixedRow(UI: any): any
		return UI.Screen("S")({ UI.HStack("Row")(withBoxes(UI, { width = FILL }, "K", 4, FIXED(160), FIXED(44))) })
	end

	-- [200][Spacer][200], whose ends alone exceed a phone
	local function spacerRow(UI: any): any
		return UI.Screen("S")({
			UI.HStack("Row")({
				width = FILL,
				UI.Box("A")({ width = FIXED(200), height = FIXED(44) }),
				UI.Spacer("Sp")({}),
				UI.Box("B")({ width = FIXED(200), height = FIXED(44) }),
			}),
		})
	end

	local function issues(build: any, combo: Combo, phrase: string?): { string }
		local _, controller = render(build, combo)
		return findings(controller, phrase)
	end

	it("a page taller than its box is DIAGNOSED at every one of the six combos", function()
		local silent: { string } = {}
		for _, combo in COMBOS do
			if #issues(tallPage, combo, "content overflows this vstack") == 0 then
				table.insert(silent, combo.name)
			end
		end
		expect(`silent:{table.concat(silent, ",")}`).toBe("silent:")
	end)

	it("...and so is a fixed row, and a Spacer row whose ends alone do not fit", function()
		local compact = COMBOS[1]
		local row = issues(fixedRow, compact)
		local spacer = issues(spacerRow, compact)
		expect(#row >= 1).toBe(true)
		expect(#spacer >= 1).toBe(true)
		expect(string.find(row[1], "content overflows this hstack", 1, true) ~= nil).toBe(true)
		expect(string.find(spacer[1], "content overflows this hstack", 1, true) ~= nil).toBe(true)
	end)

	it("THE DIAGNOSIS IS COMPLETE at every combo: container, axis, amount, both fixes", function()
		local incomplete: { string } = {}
		for _, combo in COMBOS do
			for _, issue in issues(tallPage, combo, "content overflows this vstack") do
				for _, phrase in { "on the main axis", "paint outside its box", "ScrollView", "give it room" } do
					if string.find(issue, phrase, 1, true) == nil then
						table.insert(incomplete, `{combo.name}:{phrase}`)
					end
				end
				-- ...and it carries a real pixel count
				if string.match(issue, "by (%d+)px") == nil then
					table.insert(incomplete, `{combo.name}:px`)
				end
			end
		end
		expect(`incomplete:{table.concat(incomplete, ",")}`).toBe("incomplete:")
	end)

	it("CLIPPING IS NEVER THE ANSWER: nothing was quietly made a clip host", function()
		-- `ScrollView` is the one container that clips by default; a plain stack
		-- that overflows does not acquire `clipChildren`
		local adapter = render(function(UI)
			return UI.Screen("S")({
				UI.VStack("Col")({}),
				UI.HStack("Row")({}),
				UI.VStack("V")({ overflow = "clip" }),
			})
		end, COMBOS[1])
		expect(adapter.node("/S/Col").props.clipChildren).toBeNil()
		expect(adapter.node("/S/Row").props.clipChildren).toBeNil()
		-- ...and the one word that makes a clip host still does
		expect(adapter.node("/S/V").props.clipChildren).toBe(true)
	end)
end)

-- A ten-foot Composition caps its main lane at 900 = `adaptive.LANE_MEASURE`
-- times the ten-foot metric scale. It is a default: an authored `maxMeasure` or
-- group `maxWidth` wins.
describe("B-6e — the ten-foot Composition measure caps at the ruled 900", function()
	local function compositionScreen(maxMeasure: number?, mainMaxWidth: number?)
		return function(UI: any): any
			return UI.Screen("S")({
				UI.Composition("Sum")({
					arrangements = { "threeLane", "twoLane", "column" },
					laneGap = "m",
					groupGap = "s",
					width = FILL,
					height = FILL,
					maxMeasure = maxMeasure,
					groups = {
						{ id = "lead", lane = "lead", sizing = "hug", place = "center" },
						{
							id = "main",
							lane = "main",
							sizing = "fill",
							weight = 1,
							minWidth = 240,
							maxWidth = mainMaxWidth,
						},
						{ id = "trail", lane = "trail", sizing = "hug", place = "center" },
					},
					UI.Region("Hero")({
						group = "lead",
						rank = 3,
						UI.Box("HeroBox")({ width = FIXED(200), height = FIXED(120) }),
					}),
					UI.Region("Field")({
						group = "main",
						rank = 2,
						sizing = "fill",
						UI.Box("FieldBox")({ width = FILL, height = FIXED(300) }),
					}),
					UI.Region("Ctas")({
						group = "trail",
						rank = 1,
						UI.Box("CtaBox")({ width = FIXED(200), height = FIXED(80) }),
					}),
				}),
			})
		end
	end

	local function resolveAt(combo: Combo, maxMeasure: number?, mainMaxWidth: number?): (any, any)
		local adapter, controller = render(compositionScreen(maxMeasure, mainMaxWidth), combo, "coreSafeContent")
		return adapter, controller.compositionAt("/S/Sum")
	end

	local function mainLane(resolution: any): number
		for _, lane in resolution.lanes do
			-- the dump flattens a lane's affinity list to a joined string
			local affinities = if type(lane.affinities) == "table"
				then table.concat(lane.affinities, "+")
				else tostring(lane.affinities)
			if affinities == "main" then
				return lane.rect.w
			end
		end
		return -1
	end

	it("the ten-foot main lane is 900", function()
		local _, tenFoot = resolveAt(COMBOS[5])
		expect(tenFoot.arrangement).toBe("threeLane")
		expect(mainLane(tenFoot)).toBe(900)
	end)

	it("...and the derivation holds: it IS the tablet measure times the distance factor", function()
		local adaptive = require("../src/layout/adaptive")
		local snapshot = require("../src/themes/snapshot")
		expect((adaptive :: any).LANE_MEASURE * snapshot.metricScale("Large")).toBe(900)
		-- a near display takes no cap at all
		expect((adaptive :: any).laneMeasureFor(snapshot.metricScale("Medium"))).toBeNil()
	end)

	it("THE OTHER FIVE COMBOS DO NOT MOVE", function()
		-- a distance rule, not a width rule: a 1600px desktop keeps its 1168px
		-- measure, and the compact phone resolves `column` with no main lane
		local widths: { string } = {}
		for index, combo in COMBOS do
			if index == 5 then
				continue
			end
			local _, resolution = resolveAt(combo)
			table.insert(widths, `{resolution.arrangement}:{mainLane(resolution)}`)
		end
		expect(table.concat(widths, " ")).toBe("column:-1 threeLane:412 threeLane:592 threeLane:1168 threeLane:848")
	end)

	it("the lanes re-absorb the slack and the band is CENTRED, not parked left", function()
		-- 200 lead + 24 + 900 main + 24 + 200 trail = 1348 inside a 1740 content
		-- box, so 196px of slack on each side
		local adapter, tenFoot = resolveAt(COMBOS[5])
		local hero = adapter.node("/S/Sum/Hero").rect
		local ctas = adapter.node("/S/Sum/Ctas").rect
		local screen = adapter.node("/S/Sum").rect
		local leftGap = hero.x - screen.x
		local rightGap = (screen.x + screen.w) - (ctas.x + ctas.w)
		expect(`{leftGap}/{rightGap}`).toBe("196/196")
		expect(tenFoot.used.w).toBe(1348)
	end)

	it("AUTHORED WINS: a declared `maxMeasure` is not second-guessed at ten-foot", function()
		-- 1600 is above the cap, so only an inert default reaches 1152:
		-- 1600 box - 200 lead - 200 trail - 48 of gaps
		local _, authored = resolveAt(COMBOS[5], 1600)
		expect(mainLane(authored)).toBe(1152)
	end)

	it("...and so does a group that declares its own `maxWidth`", function()
		local _, tighter = resolveAt(COMBOS[5], nil, 700)
		expect(mainLane(tighter)).toBe(700)
	end)
end)
