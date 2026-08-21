--!strict
--[[
	THE LAYOUT PRIMITIVES ANSWER FOR THEMSELVES (wave LAYOUT-FIX, 2026-08-21).

	`artifacts/release-candidate-review/adapt-audit/matrix-layout.md` measured the
	six screen-size × input combos against every layout primitive and found the same
	defect shape eight times over: **an adaptive rule that exists, is correct, is
	unit-tested, and is not reached on the default path.** `Grid` defaults to one
	lane. `AdaptiveStack` defaults to not adapting. The default answer to overflow
	is to paint outside the box.

	This file is the standing guard for the halves of that this wave closed. Every
	case here was RED at the wave's anchor (`fd59cae`) — that is the point of the
	file, and the report records which mutation reddens which case.

	THE SIX COMBOS ARE THE AUDIT'S OWN, verbatim from its column table, so a row
	here can be read straight against the row there:

	  compact touch portrait    390x844   Small
	  compact touch landscape   844x390   Small
	  regular touch tablet     1024x768   Small
	  desktop pointer          1600x900   Medium
	  ten-foot gamepad        1920x1080   Large
	  hybrid pointer+touch     1280x800   Medium
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local UI = require("../src/blueprint")
local customFactory = require("../src/core/custom")
local environment = require("../src/env/environment")
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")

local FIXED = function(px: number)
	return { type = "fixed", px = px }
end

type Combo = { name: string, w: number, h: number, display: string }
local COMBOS: { Combo } = {
	{ name = "compact touch portrait", w = 390, h = 844, display = "Small" },
	{ name = "compact touch landscape", w = 844, h = 390, display = "Small" },
	{ name = "regular touch tablet", w = 1024, h = 768, display = "Small" },
	{ name = "desktop pointer", w = 1600, h = 900, display = "Medium" },
	{ name = "ten-foot gamepad", w = 1920, h = 1080, display = "Large" },
	{ name = "hybrid pointer+touch", w = 1280, h = 800, display = "Medium" },
}

local function render(screen: any, combo: Combo, policy: string?): (any, any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = combo.w, h = combo.h })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	env:set("displaySize", combo.display)
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = policy or "edgeToEdge" })
	controller.initialRender()
	return adapter, controller
end

-- how many cells share the first cell's LANE coordinate — i.e. the lane count the
-- grid actually laid out, read off the rects rather than off the arithmetic
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

local function cards(n: number, w: number, h: number): { any }
	local kids = {}
	for i = 1, n do
		kids[i] = UI.Box({ id = "C" .. i, width = FIXED(w), height = FIXED(h) })
	end
	return kids
end

--[[ ═══ ADAPT-L2 · a Grid that was told nothing lanes itself from the box it got ═══

	`gridLaneCount` returned 1 whenever neither `columns` nor `minColumnWidth` was
	declared, at every width from 390 to 1920 — cell B-1, "a one-lane default on a
	1920 TV is a column of cards down the left edge".

	The default is now the route the guide already teaches: the widest child's own
	measured extent as the lane minimum, divided into the box the grid was actually
	offered by `adaptive.columnsFor` — the same function the declared route calls,
	so the ten-foot cap rides along and a television gets FEWER lanes than a
	desktop. No new number enters the framework.
]]
describe("ADAPT-L2 — Grid lanes itself from the space it got", function()
	-- the audit's own B-2 row, which is the number the default must now reach:
	-- six 160px cards at each combo with `minColumnWidth = 160` declared
	local EXPECTED = { 2, 4, 6, 9, 5, 7 }

	for index, combo in COMBOS do
		it(`an undeclared Grid takes the offer's lanes at {combo.name}`, function()
			local screen = UI.Screen({
				id = "S",
				children = { UI.Grid({ id = "G", gap = 12, children = cards(14, 160, 100) }) },
			})
			local adapter = render(screen, combo)
			expect(laneCount(adapter, "/S/G/C", 14)).toBe(EXPECTED[index])
		end)
	end

	it("the undeclared answer IS the declared answer, at every combo", function()
		-- the strongest form of the claim: the default is not a second arithmetic
		-- that happens to agree today, it is the same one reached with the
		-- minimum the solver already measured
		for _, combo in COMBOS do
			local declared = render(
				UI.Screen({
					id = "S",
					children = { UI.Grid({ id = "G", gap = 12, minColumnWidth = 160, children = cards(14, 160, 100) }) },
				}),
				combo
			)
			local defaulted = render(
				UI.Screen({
					id = "S",
					children = { UI.Grid({ id = "G", gap = 12, children = cards(14, 160, 100) }) },
				}),
				combo
			)
			expect(laneCount(defaulted, "/S/G/C", 14)).toBe(laneCount(declared, "/S/G/C", 14))
		end
	end)

	it("a television gets FEWER lanes than a desktop, with nothing declared", function()
		local function lanes(combo: Combo): number
			local screen = UI.Screen({
				id = "S",
				children = { UI.Grid({ id = "G", gap = 12, children = cards(14, 160, 100) }) },
			})
			return laneCount(render(screen, combo), "/S/G/C", 14)
		end
		local desktop = lanes(COMBOS[4])
		local tenFoot = lanes(COMBOS[5])
		expect(tenFoot).toBeLessThan(desktop)
	end)

	it("AUTHORED ALWAYS WINS: a declared lane count is untouched by the default", function()
		local screen = UI.Screen({
			id = "S",
			children = { UI.Grid({ id = "G", gap = 12, columns = 3, children = cards(9, 160, 100) }) },
		})
		for _, combo in COMBOS do
			expect(laneCount(render(screen, combo), "/S/G/C", 9)).toBe(3)
		end
	end)

	it("...and so is a declared minimum, in both directions", function()
		local wide = UI.Screen({
			id = "S",
			children = { UI.Grid({ id = "G", gap = 12, minColumnWidth = 700, children = cards(6, 160, 100) }) },
		})
		local narrow = UI.Screen({
			id = "S",
			children = { UI.Grid({ id = "G", gap = 12, minColumnWidth = 40, children = cards(6, 160, 100) }) },
		})
		-- a minimum WIDER than the children still wins: two lanes on a 1600 desktop,
		-- not the nine the children's own 160px would have bought
		expect(laneCount(render(wide, COMBOS[4]), "/S/G/C", 6)).toBe(2)
		-- ...and one NARROWER than them wins too — six lanes, one per child
		expect(laneCount(render(narrow, COMBOS[4]), "/S/G/C", 6)).toBe(6)
	end)

	it("THE NULL HYPOTHESIS: a grid of fill children still gets one lane", function()
		-- a `fill` child cannot express an intrinsic minimum (it measures to
		-- whatever it is offered), so the honest answer is the one-lane fallback
		-- the declared `"intrinsic"` route has always given — unchanged
		local kids = {}
		for i = 1, 6 do
			kids[i] = UI.Box({ id = "C" .. i, width = { type = "fill", weight = 1 }, height = FIXED(40) })
		end
		local screen = UI.Screen({ id = "S", children = { UI.Grid({ id = "G", gap = 12, children = kids }) } })
		expect(laneCount(render(screen, COMBOS[4]), "/S/G/C", 6)).toBe(1)
	end)
end)

--[[ ═══ ADAPT-L4 · a class named AdaptiveStack cannot silently not adapt ═══════

	`axis` defaulted to `"y"`, so `UI.AdaptiveStack{}` was a PERMANENT VSTACK at
	every combo — measured 160x200 at all six, 1920px television included (cell
	A-2). Three shipped fixtures declared it with a comment saying "side by side
	where there is room, a column where there is not" and never went side by side.

	The remedy is this framework's own, and it is older than the audit:
	`tab_view.luau:344-350` REFUSES to construct when its adaptive fact is absent,
	naming the host that would have supplied it. `axis` is now REQUIRED, and its
	refusal names both routes — the reactive fact for a stack that adapts, and
	`UI.VStack` for an author who simply wants a column. A default of `"y"` on
	THIS class buys nothing that `UI.VStack` did not already buy.
]]
describe("ADAPT-L4 — AdaptiveStack refuses rather than silently not adapting", function()
	it("a bare AdaptiveStack REFUSES to construct", function()
		expect(function()
			UI.AdaptiveStack({ id = "Panels", gap = 8, children = { UI.Box({ id = "A" }) } })
		end).toThrow()
	end)

	it("...and the refusal names the host, the fact, and the unconditional class", function()
		local ok, err = pcall(function()
			UI.AdaptiveStack({ id = "Panels", gap = 8, children = { UI.Box({ id = "A" }) } })
		end)
		expect(ok).toBe(false)
		local message = tostring(err)
		local missing: { string } = {}
		-- the fix, the host that publishes it, and the way out for an author who
		-- wanted a column all along — the same three the tab_view refusal carries
		for _, phrase in { "AdaptiveStack.axis is required", "adaptive.conditions", "client.host.new", "UI.VStack" } do
			if string.find(message, phrase, 1, true) == nil then
				table.insert(missing, phrase)
			end
		end
		expect(`missing:{table.concat(missing, ",")}`).toBe("missing:")
	end)

	it("THE NULL HYPOTHESIS: a bound axis constructs and still flips in place", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 800 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local scope = core:scope("adapt-l4")
		local conditions = (require("../src/layout/adaptive") :: any).conditions(core, env, { scope = scope })
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.AdaptiveStack({
					id = "Bar",
					axis = conditions.axis,
					gap = 8,
					children = {
						UI.Box({ id = "A", width = FIXED(60), height = FIXED(20) }),
						UI.Box({
							id = "B",
							width = FIXED(60),
							height = FIXED(20),
						}),
					},
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local column = adapter.node("/S/Bar/B").rect
		env:set("viewportRect", { x = 0, y = 0, w = 900, h = 800 })
		controller.refresh()
		local row = adapter.node("/S/Bar/B").rect
		-- a column puts B under A; a row puts it beside it. The class's whole
		-- promise is that this is a re-solve, so the node is the same node
		expect(`{column.x},{column.y} -> {row.x},{row.y}`).toBe("0,28 -> 68,0")
		scope:dispose()
	end)

	it("the comment three fixtures carried is TRUE now: 320px is a column, 1280px a row", function()
		-- the audit's own reproduction: two 132px plates cannot share a 320px line,
		-- and the fixtures said so in a comment while stacking forever
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local scope = core:scope("adapt-l4-fixture")
		local conditions = (require("../src/layout/adaptive") :: any).conditions(core, env, { scope = scope })
		local function panels(): any
			return UI.Screen({
				id = "S",
				children = {
					UI.AdaptiveStack({
						id = "Panels",
						axis = conditions.axis,
						gap = 8,
						width = { type = "fill", weight = 1 },
						children = {
							UI.Box({ id = "One", width = FIXED(132), height = FIXED(60) }),
							UI.Box({ id = "Many", width = FIXED(132), height = FIXED(60) }),
						},
					}),
				},
			})
		end
		env:set("viewportRect", { x = 0, y = 0, w = 320, h = 640 })
		local root = mountLib.mount(core, panels())
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		expect(adapter.node("/S/Panels/Many").rect.y).toBe(68)
		env:set("viewportRect", { x = 0, y = 0, w = 1280, h = 800 })
		controller.refresh()
		-- ...and on a wide surface they are the comparison the comment promised
		expect(adapter.node("/S/Panels/Many").rect.y).toBe(0)
		scope:dispose()
	end)
end)

--[[ ═══ ADAPT-L3 · the adaptive axis is a SCREEN fact, and the band where that bites ═══

	CONTESTED, and this block is the measurement that makes the contest checkable
	rather than a paragraph. `conditions.axis` is `adaptive.axisFor(viewportWidth)`
	— the RAW window — so a stack inside anything that got less than the window can
	be told "row" for space it does not have. Reproduced below with nothing exotic:
	a `Screen` with the theme's own 24px page margin.

	WHY THE TWO CANDIDATE FIXES ARE BOTH OUT OF THIS WAVE'S REACH, stated here so
	the next reader does not re-derive it:

	  (a) "make `contentWidth` subtract the insets and leave `viewportWidth` raw" is
	      refused by the framework's own deprecation ledger — `src/init.luau`
	      DEPRECATED `adaptive.conditions().contentWidth` at 0.8.0 with the
	      replacement `viewportWidth` and the note "alias; the value never
	      subtracted insets". Giving a removed-by-0.9.0 alias new meaning is the
	      opposite of what that row promised. It also would not close the case
	      below, which is PADDING rather than an inset.
	  (b) "let the stack resolve its axis from the box the solver proposed" is the
	      honest fix and it is not one file. The axis is currently a PROP, and
	      `present/focus_map.luau:640-665` reads that prop LIVE to decide whether a
	      pad navigates the stack left/right or up/down — the D5 defect that had
	      every segmented picker navigating vertically. An offer-derived axis is
	      known only inside the solve, so it needs the solver to publish the
	      resolved axis per node AND the focus derivation to read the solved fact
	      instead of the prop, which crosses solver, renderer and presenter — all
	      three extraction-locked.

	So the band stays, and it is guarded: the framework is not silent about it, and
	the case below is the red one waiting for (b).
]]
describe("ADAPT-L3 — the axis is the SCREEN's width, and the solver says so", function()
	local adaptive = require("../src/layout/adaptive")

	local function padded(width: number): (any, any, any)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = width, h = 800 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local scope = core:scope("adapt-l3")
		local conditions = (adaptive :: any).conditions(core, env, { scope = scope })
		local kids = {}
		for i = 1, 3 do
			kids[i] = UI.Box({ id = "K" .. i, width = FIXED(200), height = FIXED(44) })
		end
		local screen = UI.Screen({
			id = "S",
			padding = "l",
			children = {
				UI.AdaptiveStack({
					id = "Bar",
					axis = conditions.axis,
					gap = 8,
					width = { type = "fill", weight = 1 },
					children = kids,
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return adapter, controller, scope
	end

	local function overflowFinding(controller: any): string?
		for _, d in controller.diagnostics() do
			if string.find(d.issue, "content overflows", 1, true) ~= nil then
				return d.issue
			end
		end
		return nil
	end

	it("the band exists and is exactly the offer's, not the window's", function()
		-- 560: the window is under the threshold, so it is a column and fits
		local _, below, s1 = padded(560)
		expect(overflowFinding(below)).toBeNil()
		s1:dispose()
		-- 600-640: the WINDOW cleared the threshold and the CONTAINER did not
		for _, width in { 600, 610, 640 } do
			local _, inside, s2 = padded(width)
			expect(overflowFinding(inside) ~= nil).toBe(true)
			s2:dispose()
		end
		-- 680: the container clears it too, and the band closes
		local _, above, s3 = padded(680)
		expect(overflowFinding(above)).toBeNil()
		s3:dispose()
	end)

	it("...and it is NOT silent — the finding names the container, the amount and both fixes", function()
		local _, controller, scope = padded(610)
		local issue = overflowFinding(controller) :: string
		local missing: { string } = {}
		for _, phrase in { "hstack", "54px", "paint outside its box", "ScrollView", "give it room" } do
			if string.find(issue, phrase, 1, true) == nil then
				table.insert(missing, phrase)
			end
		end
		expect(`missing:{table.concat(missing, ",")}`).toBe("missing:")
		scope:dispose()
	end)

	it("the fact itself is honest about what it is: `viewportWidth` IS the raw window", function()
		-- the module's own V16 note, pinned: a decision keyed on this is keyed on
		-- the WINDOW. `contentWidth` is its deprecated alias and is the same number.
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1920, h = 1080 })
		env:set("displaySize", "Large")
		local scope = core:scope("adapt-l3-fact")
		local conditions = (adaptive :: any).conditions(core, env, { scope = scope })
		-- 90px of overscan per side is reserved at ten-foot and this number ignores it
		expect(conditions.viewportWidth:get()).toBe(1920)
		expect(conditions.contentWidth:get()).toBe(1920)
		scope:dispose()
	end)
end)

--[[ ═══ ADAPT-L8 · a GridRow squeezed past its declared widths and said nothing ═══

	Two containers in one primitive family with OPPOSITE failure modes, and the
	silent one was winning. At 320px three cells each declaring `width = fixed(200)`
	came out 101px wide with ZERO solver findings (cell B-4, measured 200 -> 181 ->
	148 -> 124 -> 101 across 1024/560/460/390/320), while the `UI.HStack` twin at
	the same widths files a named finding every time.

	The squeeze itself is RIGHT and stays: a row grid's naturals that do not fit
	would paint outside the box, and reducing them proportionally is the same clamp
	the flow grid makes one level up. What was wrong is that a declared `fixed(200)`
	silently became 101 — the audit's own minimum was "at minimum the finding an
	HStack files at the same width", and that is what this is.

	ONE OWNER, as everywhere in this file: the squeeze is computed in
	`gridColumnPlan`, which is the single function measure and arrange both read, so
	the finding reports the plan's own number rather than a second arithmetic that
	agrees today.
]]
describe("ADAPT-L8 — a row grid says when it squeezed its columns", function()
	local function rowGrid(width: number): (any, any)
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = width, h = 800 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local cells = {}
		for i = 1, 3 do
			cells[i] = UI.Text({ id = "C" .. i, text = "Cell " .. i, width = FIXED(200), height = FIXED(24) })
		end
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.Grid({
					id = "G",
					gap = 8,
					width = { type = "fill", weight = 1 },
					children = { UI.GridRow({ id = "Row", children = cells }) },
				}),
			},
		})
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return adapter, controller
	end

	local function squeezeFinding(controller: any): string?
		for _, d in controller.diagnostics() do
			if string.find(d.issue, "squeezed its columns", 1, true) ~= nil then
				return d.issue
			end
		end
		return nil
	end

	it("a squeeze is REPORTED, at every width the audit measured one", function()
		-- 1024 and 700 hold the three 200px cells whole: no squeeze, no finding
		for _, width in { 1024, 700 } do
			local adapter, controller = rowGrid(width)
			expect(adapter.node("/S/G/Row/C1").rect.w).toBe(200)
			expect(squeezeFinding(controller)).toBeNil()
		end
		-- ...and below that the columns give, which is right, and is now said
		for _, width in { 560, 460, 390, 320 } do
			local adapter, controller = rowGrid(width)
			expect(adapter.node("/S/G/Row/C1").rect.w).toBeLessThan(200)
			expect(squeezeFinding(controller) ~= nil).toBe(true)
		end
	end)

	it("...and the finding names the amount, the room, and the three ways out", function()
		local _, controller = rowGrid(320)
		local issue = squeezeFinding(controller) :: string
		local missing: { string } = {}
		-- 600px of naturals against 304px of room after two 8px gaps
		for _, phrase in { "600px", "304px", "ScrollView", "give the grid room", "fewer columns" } do
			if string.find(issue, phrase, 1, true) == nil then
				table.insert(missing, phrase)
			end
		end
		expect(`missing:{table.concat(missing, ",")}`).toBe("missing:")
	end)

	it("THE GEOMETRY DID NOT MOVE: the squeeze is still the squeeze", function()
		-- the clamp is right and this wave did not touch it — only the silence.
		-- These are the audit's own measured numbers, so a "fix" that re-laid the
		-- row out would fail here rather than pass quietly
		local widths: { number } = {}
		for _, vp in { 1024, 560, 460, 390, 320 } do
			local adapter = rowGrid(vp)
			table.insert(widths, adapter.node("/S/G/Row/C1").rect.w)
		end
		expect(table.concat(widths, ",")).toBe("200,181,148,124,101")
	end)
end)

--[[ ═══ ADAPT-L5 · the default answer to overflow, measured at all six combos ═══

	CONTESTED as a DEFAULT, guarded as a DIAGNOSIS. The audit reached this from
	three directions — a row of fixed boxes 274px over at compact, a Spacer layout
	whose two ends alone exceed the width, and a twenty-row page 792-1362px over at
	every combo — and got the same outcome each time: the content is placed past the
	edge, nothing clips it, and a finding is filed on a channel that must be asked.

	WHAT THIS WAVE COULD NOT DO, per cell and with the reason, because "we did not
	get to it" and "it is not one file" are different sentences:

	  * F-1's expected answer is an IMPLICIT SCROLL HOST for a page taller than its
	    box. `render/renderer.luau:1483` keys the engine scroll host on
	    `node.class == "ScrollView"`, not on the solved kind — so a `kind = "scroll"`
	    written at the measure seam would get a scroller's LAYOUT and no scrolling,
	    which is strictly worse than today. Renderer and solver, both locked.
	  * A-8/F-2's expected answer is `wrap` BOUND BY DEFAULT on a stack that does
	    not fit. `wrap` decides the solver KIND (`hstack` vs `hwrap`) at the measure
	    seam, and `hwrap` has no shrink pair by design — so wrapping by default would
	    silently disable the shrink cascade on every stack that has one, which is
	    the "silent re-flow of shipped screens" the solver's own overflow comment
	    has always refused to be.
	  * F-4's expected MINIMUM — "the solver's finding should escalate" — is the
	    half that is already shipped, and it is worth saying so rather than
	    re-building it: `tests/overflow_sweep.spec.luau` asks EVERY showcase surface
	    at nine viewports, four text preferences and the themed and locale tiers, on
	    every `./run-tests.sh`, with nobody deciding to run it.

	So what is left for this file is the part the sweep structurally cannot say: that
	the DIAGNOSIS itself is complete and identical at every combo, on all three of
	the audit's shapes. A finding that named the container on a phone and not on a
	television would be a hole the sweep could not see, because the sweep only ever
	counts findings.
]]
describe("ADAPT-L5 — overflow is not silent, and says the same thing at every combo", function()
	local function findings(controller: any): { string }
		local out: { string } = {}
		for _, d in controller.diagnostics() do
			table.insert(out, d.issue)
		end
		return out
	end

	local function mount(screen: any, combo: Combo): any
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = combo.w, h = combo.h })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("displaySize", combo.display)
		local root = mountLib.mount(core, screen)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return controller
	end

	-- the audit's shape 3: twenty 80px rows on a page with no scroller
	local function tallPage(): any
		local rows = {}
		for i = 1, 20 do
			rows[i] = UI.Box({ id = "R" .. i, width = { type = "fill", weight = 1 }, height = FIXED(80) })
		end
		return UI.Screen({
			id = "S",
			children = { UI.VStack({ id = "Col", width = { type = "fill", weight = 1 }, children = rows }) },
		})
	end

	-- the audit's shape 1: four 160px boxes in a row
	local function fixedRow(): any
		local kids = {}
		for i = 1, 4 do
			kids[i] = UI.Box({ id = "K" .. i, width = FIXED(160), height = FIXED(44) })
		end
		return UI.Screen({
			id = "S",
			children = { UI.HStack({ id = "Row", width = { type = "fill", weight = 1 }, children = kids }) },
		})
	end

	-- the audit's shape 2: [200][Spacer][200], whose ends alone exceed a phone
	local function spacerRow(): any
		return UI.Screen({
			id = "S",
			children = {
				UI.HStack({
					id = "Row",
					width = { type = "fill", weight = 1 },
					children = {
						UI.Box({ id = "A", width = FIXED(200), height = FIXED(44) }),
						UI.Spacer({ id = "Sp" }),
						UI.Box({ id = "B", width = FIXED(200), height = FIXED(44) }),
					},
				}),
			},
		})
	end

	it("a page taller than its box is DIAGNOSED at every one of the six combos", function()
		local silent: { string } = {}
		for _, combo in COMBOS do
			local issues = findings(mount(tallPage(), combo))
			local named = false
			for _, issue in issues do
				if string.find(issue, "content overflows this vstack", 1, true) ~= nil then
					named = true
				end
			end
			if not named then
				table.insert(silent, combo.name)
			end
		end
		expect(`silent:{table.concat(silent, ",")}`).toBe("silent:")
	end)

	it("...and so is a fixed row, and a Spacer row whose ends alone do not fit", function()
		-- both at the compact phone the audit measured them on
		local compact = COMBOS[1]
		local row = findings(mount(fixedRow(), compact))
		local spacer = findings(mount(spacerRow(), compact))
		expect(#row >= 1).toBe(true)
		expect(#spacer >= 1).toBe(true)
		expect(string.find(row[1], "content overflows this hstack", 1, true) ~= nil).toBe(true)
		expect(string.find(spacer[1], "content overflows this hstack", 1, true) ~= nil).toBe(true)
	end)

	it("THE DIAGNOSIS IS COMPLETE at every combo: container, axis, amount, both fixes", function()
		-- the property the always-on sweep structurally cannot check, because it
		-- COUNTS findings rather than reading them: a message that named the
		-- container on a phone and not on a television is a hole nothing else sees
		local incomplete: { string } = {}
		for _, combo in COMBOS do
			local issues = findings(mount(tallPage(), combo))
			for _, issue in issues do
				if string.find(issue, "content overflows this vstack", 1, true) ~= nil then
					for _, phrase in { "on the main axis", "paint outside its box", "ScrollView", "give it room" } do
						if string.find(issue, phrase, 1, true) == nil then
							table.insert(incomplete, `{combo.name}:{phrase}`)
						end
					end
					-- ...and it carries a real pixel count, not a placeholder
					if string.match(issue, "by (%d+)px") == nil then
						table.insert(incomplete, `{combo.name}:px`)
					end
				end
			end
		end
		expect(`incomplete:{table.concat(incomplete, ",")}`).toBe("incomplete:")
	end)

	it("CLIPPING IS NEVER THE ANSWER: nothing was quietly made a clip host", function()
		-- the standing rule, pinned where the wave that could have broken it lives.
		-- `ScrollView` is the one container that clips by default; a plain stack
		-- that overflows must not acquire `clipChildren` behind the author's back
		local col = UI.VStack({ id = "Col", children = {} })
		expect(col.props.clipChildren).toBeNil()
		local row = UI.HStack({ id = "Row", children = {} })
		expect(row.props.clipChildren).toBeNil()
		-- ...and the one word that DOES make a clip host still does
		expect(UI.VStack({ id = "V", overflow = "clip", children = {} }).props.clipChildren).toBe(true)
	end)
end)
