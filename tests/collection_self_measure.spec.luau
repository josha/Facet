--!strict
--[[ A COLLECTION MEASURES THE BOX IT WAS GIVEN — `viewportExtent = "auto"` on
	`newVirtualList` and `newVirtualGrid`, and `crossExtent` on the list.

	THE GAP THIS CLOSES (purity audit §4). `viewportExtent` was asserted REQUIRED
	with no self-measuring form, and the cross axis was documented as the consumer's
	job ("wrap the list in a box of the height you want"). So every consumer that
	did not already know its own extent wrote the same arithmetic by hand: the
	gallery's `row_actions` fixture kept a `VListPane` path, an `onGeometry`
	handler, a `vlistWindow` signal and a `vlistGap()` snapshot read to subtract a
	hint and a theme gap from a solved pane; its card rail subtracted safe insets, a
	Screen padding and a scrollbar guess; Rascal Rally's sponsor surfaces
	hand-rolled `math.clamp(math.floor(h * fraction), min, max)`. Every one of those
	is the framework's own number, re-derived by somebody who could only guess at
	the terms.

	`newTable` has measured its body since the variable-extents mission, through
	exactly the seam used here — the presenter's `syncGeometry`, whose rects are
	already delivered every refresh. This promotes that private technique to a
	declared spec value.

	WHAT THIS SPEC PINS:

	  · `"auto"` windows against the SOLVED host box, not a number anyone typed;
	  · THE SEED IS THE SCREEN, and the direction is the point: the frame before a
	    measurement exists over-fills (a strict superset of what the viewport
	    touches) rather than mounting three rows and popping;
	  · CONVERGENCE IS ONE STEP AND IT STOPS — the host takes `fill`, so its size
	    is decided by what contains it and never by what is inside it, and the
	    equality guard means a settled tree writes nothing;
	  · a RESIZE re-measures, in place, with no rebuild;
	  · `crossExtent = "hug"` sizes the cross axis to the content instead of
	    filling — the horizontal rail's own defect, where `fill` "is a promise the
	    box will be big enough, and this box was not";
	  · `crossExtent = "measured"` keeps filling and REPORTS the number, so a
	    consumer reads the box it was given instead of predicting it;
	  · a list that asks for neither is byte-identical to what it always was, and
	    publishes no `crossExtent` at all.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local virtual_grid = require("../src/controls/virtual_grid")
local worldLib = require("./lib/world")

local function makeRows(n: number): { { id: string, label: string } }
	local rows = table.create(n)
	for i = 1, n do
		rows[i] = { id = `r{i}`, label = `Row {i}` }
	end
	return rows
end

--[[ A PRESENTED collection inside a pane of a DECLARED size, which is the whole
	shape under test: the pane is what the collection is given, and the two
	self-measuring forms are the claim that it can find out how big that is without
	being told. Built on `tests/lib/world.luau` rather than by hand (R12's trigger:
	the next spec that would ADD a presenter builder migrates instead). ]]
local function pane(opts: any)
	local w = worldLib.new({ viewport = opts.screen or { x = 0, y = 0, w = 800, h = 600 } })
	local rows = w.core:signal(makeRows(opts.count or 40))
	local paneMain = w.core:signal(opts.pane or 240)
	local built = opts.build(w.core, w.env, rows)
	if opts.beforePresent ~= nil then
		-- the frame before any solve exists, which is the only place a SEED can be
		-- observed at all
		opts.beforePresent(built)
	end
	local paneDim = w.core:memo(function(use)
		return { type = "fixed", px = use(paneMain) }
	end)
	--[[ `wrap` REPLACES the pane, for the cases whose whole subject is an ancestor
		that is NOT a pane — a scroller unbounded on the collection's own axis. The
		default is the pane, so every other case reads the same. ]]
	local inner = if opts.wrap ~= nil
		then opts.wrap(built.blueprint)
		else Facet.UI.VStack({
			id = "Pane",
			padding = 0,
			gap = 0,
			-- the pane is FIXED on y and FILLS on x, so a vertical list's SCROLL
			-- axis and a horizontal rail's CROSS axis are both the number under
			-- test, and neither is the screen's
			width = { type = "fill", weight = 1 },
			height = paneDim,
			children = { built.blueprint },
		})
	w.present(Facet.UI.Screen({ id = "S", padding = 0, gap = 0, children = { inner } }))
	return {
		core = w.core,
		env = w.env,
		pres = w.pres,
		rows = rows,
		paneMain = paneMain,
		control = built,
		rect = function(path: string): any
			return w.controller.rectOf(path)
		end,
	}
end

describe('viewportExtent = "auto": the list measures the box it was given', function()
	it("windows against the SOLVED host box, with no number handed in", function()
		local w = pane({
			pane = 240,
			build = function(core: any, env: any, rows: any)
				return virtual_list.build(Facet, core, {
					id = "VL",
					rows = rows,
					env = env,
					key = function(item: any)
						return item.id
					end,
					itemExtent = 40,
					viewportExtent = "auto",
					overscan = 0,
					cell = function(item: any)
						return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
					end,
				})
			end,
		})
		-- the pane is 240 tall and the list is its only child, so the list's own
		-- solved box IS 240 — and that is the number the window is taken against
		expect(w.rect("/S/Pane/VL").h).toBe(240)
		expect(w.control.dump().viewportExtent).toBe(240)
		-- 240 / 40 = six whole rows, no overscan
		expect(#w.control.dump().window).toBe(6)
		w.control.dispose()
	end)

	it("SEEDS FROM THE SCREEN, so the frame before a measurement over-fills", function()
		--[[ THE DIRECTION IS THE WHOLE POINT (newTable's own argument, promoted). A
			seed of 0 mounts `1 .. 1 + overscan` on the first frame — three rows in a
			six-hundred-pixel box, and a visible pop when the measurement lands. A
			box is never bigger than the surface that contains it, so the screen is a
			sound UPPER bound and the first frame is a strict SUPERSET of what the
			viewport touches. ]]
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local rows = core:signal(makeRows(400))
		local list = virtual_list.build(Facet, core, {
			id = "VL",
			rows = rows,
			env = env,
			key = function(item: any)
				return item.id
			end,
			itemExtent = 40,
			viewportExtent = "auto",
			overscan = 0,
			cell = function(item: any)
				return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
		})
		-- no presenter, no solve: this is the seed, and it is the screen's height
		expect(list.dump().viewportExtent).toBe(600)
		expect(#list.dump().window).toBe(15)
		list.dispose()
		-- ...and with no environment at all there is no screen to ask, which is the
		-- headless case and is 0
		local bare = Facet.newCore()
		local headless = virtual_list.build(Facet, bare, {
			id = "VL",
			rows = bare:signal(makeRows(10)),
			key = function(item: any)
				return item.id
			end,
			itemExtent = 40,
			viewportExtent = "auto",
			cell = function()
				return Facet.UI.Text({ id = "L", text = "x", textSize = 14 })
			end,
		})
		expect(headless.dump().viewportExtent).toBe(0)
		headless.dispose()
	end)

	it("a RESIZE re-measures in place, and a settled tree writes nothing", function()
		local w = pane({
			pane = 240,
			build = function(core: any, env: any, rows: any)
				return virtual_list.build(Facet, core, {
					id = "VL",
					rows = rows,
					env = env,
					key = function(item: any)
						return item.id
					end,
					itemExtent = 40,
					viewportExtent = "auto",
					overscan = 0,
					cell = function(item: any)
						return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
					end,
				})
			end,
		})
		expect(w.control.dump().viewportExtent).toBe(240)
		w.paneMain:set(400)
		w.pres.refresh()
		expect(w.control.dump().viewportExtent).toBe(400)
		expect(#w.control.dump().window).toBe(10)
		--[[ CONVERGENCE, ASSERTED RATHER THAN ASSUMED. The host takes `fill`, so its
			solved size is decided by what CONTAINS it and never by what is inside it
			— measuring cannot change what was measured. The observable form of that
			claim: a refresh over a settled tree changes nothing, so the signal is
			not being written to its own value on every frame (which would re-solve
			the tree forever). ]]
		local writes = 0
		w.core:observe((w.control :: any).viewportExtent, function()
			writes += 1
		end)
		w.pres.refresh()
		w.pres.refresh()
		expect(writes).toBe(0)
		w.control.dispose()
	end)

	it("newVirtualGrid takes it too, on its own scroll axis", function()
		local w = pane({
			pane = 300,
			count = 60,
			build = function(core: any, env: any, rows: any)
				return virtual_grid.build(Facet, core, {
					id = "VG",
					items = rows,
					env = env,
					key = function(item: any)
						return item.id
					end,
					columns = 3,
					itemExtent = 50,
					viewportExtent = "auto",
					overscan = 0,
					cell = function(item: any)
						return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
					end,
				})
			end,
		})
		expect(w.rect("/S/Pane/VG").h).toBe(300)
		-- 300 / 50 = six whole LINES of three
		expect(w.control.dump().lines[2] - w.control.dump().lines[1] + 1).toBe(6)
		w.control.dispose()
	end)

	it("a number and a Readable still work, and are still refused when they are neither", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(4))
		local function build(viewport: any)
			return virtual_list.build(Facet, core, {
				id = "VL",
				rows = rows,
				key = function(item: any)
					return item.id
				end,
				itemExtent = 40,
				viewportExtent = viewport,
				cell = function()
					return Facet.UI.Text({ id = "L", text = "x", textSize = 14 })
				end,
			})
		end
		expect(build(200).dump().viewportExtent).toBe(200)
		expect(build(core:signal(120)).dump().viewportExtent).toBe(120)
		-- a word that is not "auto" is an authoring mistake, not a silent fallback
		expect(pcall(function()
			build("tall")
		end)).toBe(false)
		expect(pcall(function()
			build(0)
		end)).toBe(false)
	end)
end)

describe('viewportExtent = "auto": the measurement that is NOT a viewport', function()
	--[[ THE DEFECT THIS REPORTS, and it was found by review rather than by a
		failing assertion, which is the whole reason it needs a case.

		`"auto"` takes `fill` along its own axis. A `fill` dim offered `math.huge`
		answers with its CONTENT contribution (`layout/solver.luau`'s `fill` branch),
		a scroll node offers its children `math.huge` on the axis it scrolls, and a
		scroll node's own content measure SUMS its children. So an `"auto"`
		collection nested inside ANOTHER scroller's own scroll axis is handed a rect
		the size of its WHOLE CANVAS — and windows every row. Virtualization silently
		off, stable across every frame, and invisible to any assertion about
		correctness: the rows are all there and all in the right place. It is a
		performance cliff wearing a correct-looking layout.

		THE TEST IS THE SEED'S OWN ARGUMENT TURNED AROUND. `"auto"` seeds from the
		screen because "a box is never bigger than the surface that contains it". A
		measured extent that EXCEEDS the screen is therefore not a box at all; it is
		a canvas. The list reports it and does NOT clamp, because clamping the window
		while the solver still paints the host at canvas height would empty the
		bottom of the painted box — a visible defect traded for an invisible one. ]]
	it("a list nested in another scroller's SCROLL axis measures its whole canvas, and says so", function()
		local w = pane({
			count = 400,
			build = function(core: any, env: any, rows: any)
				return virtual_list.build(Facet, core, {
					id = "VL",
					rows = rows,
					env = env,
					key = function(item: any)
						return item.id
					end,
					itemExtent = 40,
					viewportExtent = "auto",
					overscan = 0,
					cell = function(item: any)
						return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
					end,
				})
			end,
			wrap = function(blueprint: any)
				return Facet.UI.ScrollView({
					id = "Page",
					axis = "y",
					padding = 0,
					gap = 0,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = { blueprint },
				})
			end,
		})
		local d = w.control.dump()
		-- MEASURED, not asserted from theory: 400 rows of 40px on a 600px screen
		expect(d.viewportExtent).toBe(400 * 40)
		expect(#d.window).toBe(400)
		expect(#d.diagnostics).toBe(1)
		expect(string.find(d.diagnostics[1], "CANVAS, not a viewport", 1, true) ~= nil).toBe(true)
		-- the message carries BOTH numbers, or the reader cannot tell how far out it is
		expect(string.find(d.diagnostics[1], "16000px", 1, true) ~= nil).toBe(true)
		expect(string.find(d.diagnostics[1], "600px", 1, true) ~= nil).toBe(true)
		w.control.dispose()
	end)

	it("NEGATIVE CONTROL: a list in a real pane reports NOTHING, however many rows it has", function()
		-- the same 400 rows, the only difference being an ancestor with a definite
		-- extent — so the case above cannot be passing because the diagnostic always
		-- fires, and cannot be passing because 400 rows is itself the trigger
		local w = pane({
			pane = 240,
			count = 400,
			build = function(core: any, env: any, rows: any)
				return virtual_list.build(Facet, core, {
					id = "VL",
					rows = rows,
					env = env,
					key = function(item: any)
						return item.id
					end,
					itemExtent = 40,
					viewportExtent = "auto",
					overscan = 0,
					cell = function(item: any)
						return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
					end,
				})
			end,
		})
		local d = w.control.dump()
		expect(`{d.viewportExtent}|{#d.window}|{#d.diagnostics}`).toBe("240|6|0")
		w.control.dispose()
	end)

	it("a grid says the same thing about the same shape", function()
		local w = pane({
			count = 300,
			build = function(core: any, env: any, rows: any)
				return virtual_grid.build(Facet, core, {
					id = "VG",
					items = rows,
					env = env,
					key = function(item: any)
						return item.id
					end,
					columns = 3,
					itemExtent = 50,
					viewportExtent = "auto",
					overscan = 0,
					cell = function(item: any)
						return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
					end,
				})
			end,
			wrap = function(blueprint: any)
				return Facet.UI.ScrollView({
					id = "Page",
					axis = "y",
					padding = 0,
					gap = 0,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = { blueprint },
				})
			end,
		})
		expect(#w.control.dump().diagnostics).toBe(1)
		w.control.dispose()
	end)
end)

describe('viewportExtent = "auto" + itemExtent = "cards": the seed is not an arrangement', function()
	--[[ THE SUPERSET ARGUMENT COVERS WINDOWING AND NOT PAINT (fix round 1, finding
		B). Over-estimating a viewport mounts more rows than the box touches, which
		is bounded and invisible. `itemExtent = "cards"` makes the same number decide
		how many whole cards belong in view — a PARADIGM decision, and `card_rail`'s
		own header says in capitals that it must be asked about the rail's own extent
		rather than the screen's.

		MEASURED before the fix: a 300px rail on an 800px screen resolved a THREE-UP
		arrangement of 261px cards on its first painted frame and a ONE-UP 270px
		carousel on its second. Not a size that popped — a different answer. ]]
	it("a card rail paints NOTHING before it has been measured, then the right arrangement", function()
		local w = pane({
			axis = "x",
			pane = 200,
			count = 200,
			build = function(core: any, env: any, rows: any)
				return virtual_list.build(Facet, core, {
					id = "Rail",
					axis = "x",
					rows = rows,
					env = env,
					key = function(item: any)
						return item.id
					end,
					itemExtent = "cards",
					viewportExtent = "auto",
					rowGap = 8,
					overscan = 0,
					cell = function(item: any)
						return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14, lineLimit = 1 })
					end,
				})
			end,
			beforePresent = function(built: any)
				-- the frame before any solve: a card rail seeds 0, so it commits to no
				-- arrangement at all rather than to the screen's
				expect(built.dump().viewportExtent).toBe(0)
				expect(#built.dump().window).toBe(0)
			end,
		})
		-- ...and once the solver has answered, the arrangement is the RAIL's
		local d = w.control.dump()
		expect(d.viewportExtent).toBe(784) -- 800 less the content gutter each side
		expect(#d.window > 0).toBe(true)
		w.control.dispose()
	end)

	it("NEGATIVE CONTROL: a plain list still seeds from the screen and over-fills", function()
		-- the narrowing is to `cards` alone; every other list keeps the seed and the
		-- superset it buys, which is the case this pair would otherwise silently lose
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local list = virtual_list.build(Facet, core, {
			id = "VL",
			rows = core:signal(makeRows(400)),
			env = env,
			key = function(item: any)
				return item.id
			end,
			itemExtent = 40,
			viewportExtent = "auto",
			overscan = 0,
			cell = function()
				return Facet.UI.Text({ id = "L", text = "x", textSize = 14 })
			end,
		})
		expect(`{list.dump().viewportExtent}|{#list.dump().window}`).toBe("600|15")
		list.dispose()
	end)
end)

describe("crossExtent: the axis the list does not scroll", function()
	local function rail(core: any, env: any, rows: any, crossExtent: any): any
		return virtual_list.build(Facet, core, {
			id = "VL",
			axis = "x",
			rows = rows,
			env = env,
			key = function(item: any)
				return item.id
			end,
			itemExtent = 60,
			viewportExtent = "auto",
			crossExtent = crossExtent,
			overscan = 0,
			cell = function(item: any)
				return Facet.UI.VStack({
					id = "Card",
					padding = 8,
					gap = 0,
					width = { type = "fill", weight = 1 },
					children = { Facet.UI.Text({ id = "Label", text = item.label, textSize = 14, lineLimit = 1 }) },
				})
			end,
		})
	end

	it("absent, the cross axis FILLS — every shipped list is untouched", function()
		local w = pane({
			axis = "x",
			pane = 200,
			build = function(core: any, env: any, rows: any)
				return rail(core, env, rows, nil)
			end,
		})
		expect(w.rect("/S/Pane/VL").h).toBe(200)
		-- ...and a list that asked for nothing publishes nothing
		expect((w.control :: any).crossExtent).toBe(nil)
		w.control.dispose()
	end)

	it('"hug" sizes to the content instead — the rail is as tall as its card', function()
		local w = pane({
			axis = "x",
			pane = 200,
			build = function(core: any, env: any, rows: any)
				return rail(core, env, rows, "hug")
			end,
		})
		local box = w.rect("/S/Pane/VL")
		local card = w.rect("/S/Pane/VL/Canvas/W/[r1]/Row")
		expect(card ~= nil).toBe(true)
		-- the rail hugs: it is its card's height, NOT the 200px pane it was given
		expect(box.h).toBe(card.h)
		expect(box.h < 200).toBe(true)
		-- ...and the number is reported, so a consumer never has to re-derive it
		expect((w.control :: any).crossExtent:get()).toBe(box.h)
		w.control.dispose()
	end)

	it('"measured" keeps filling and REPORTS the box it was given', function()
		local w = pane({
			axis = "x",
			pane = 200,
			build = function(core: any, env: any, rows: any)
				return rail(core, env, rows, "measured")
			end,
		})
		expect(w.rect("/S/Pane/VL").h).toBe(200)
		expect((w.control :: any).crossExtent:get()).toBe(200)
		w.paneMain:set(120)
		w.pres.refresh()
		expect((w.control :: any).crossExtent:get()).toBe(120)
		w.control.dispose()
	end)

	it('"hug" and an authored `width` are two answers to one dim, and are refused together', function()
		--[[ SELF-REVIEW FINDING, not a hypothetical: `"hug"` REPLACES the cross dim
			with `content`, so a vertical list declaring both would have had its
			`width` silently discarded — an accepted property that drives nothing,
			which is the exact class this control already refuses `cards` and
			`estimatedItemExtent` for. `"measured"` does not touch the dim, so it
			COMPOSES with `width` and is deliberately not refused. ]]
		local core = Facet.newCore()
		local rows = core:signal(makeRows(4))
		local function build(crossExtent: any, width: any)
			return virtual_list.build(Facet, core, {
				id = "VL",
				rows = rows,
				key = function(item: any)
					return item.id
				end,
				itemExtent = 40,
				viewportExtent = 200,
				crossExtent = crossExtent,
				width = width,
				cell = function()
					return Facet.UI.Text({ id = "L", text = "x", textSize = 14 })
				end,
			})
		end
		expect(pcall(function()
			build("hug", { type = "fixed", px = 300 })
		end)).toBe(false)
		-- ...and each alone is fine, so the refusal is about the PAIR
		build("hug", nil).dispose()
		build(nil, { type = "fixed", px = 300 }).dispose()
		-- ...and `"measured"` composes with a width, because it changes no dim
		build("measured", { type = "fixed", px = 300 }).dispose()
	end)

	it('"hug" works on a VERTICAL list too, where the cross axis is the WIDTH', function()
		--[[ EVERY OTHER HUG CASE IN THIS FILE IS `axis = "x"` (fix round 1, finding
			I), which is where the field's motivating defect lived — so the vertical
			half of a field documented as axis-neutral had no proof at all. Here the
			cross axis is the WIDTH: the list hugs its widest row instead of filling
			the pane it was given. ]]
		local w = pane({
			pane = 300,
			count = 6,
			build = function(core: any, env: any, rows: any)
				return virtual_list.build(Facet, core, {
					id = "VL",
					rows = rows,
					env = env,
					key = function(item: any)
						return item.id
					end,
					itemExtent = 40,
					viewportExtent = 200,
					crossExtent = "hug",
					overscan = 0,
					cell = function(item: any)
						return Facet.UI.HStack({
							id = "Card",
							padding = 8,
							gap = 0,
							children = { Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 }) },
						})
					end,
				})
			end,
		})
		local box = w.rect("/S/Pane/VL")
		local row = w.rect("/S/Pane/VL/Canvas/W/[r1]/Row")
		expect(row ~= nil).toBe(true)
		-- the list is its row's WIDTH, not the pane's — and the pane is 800 wide
		expect(box.w).toBe(row.w)
		expect(box.w < 800).toBe(true)
		-- ...and the scroll axis is untouched: it is still the number handed in
		expect(box.h).toBe(200)
		expect((w.control :: any).crossExtent:get()).toBe(box.w)
		w.control.dispose()
	end)

	it("an unknown word is refused, naming the two that are legal", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(4))
		local ok, err = pcall(function()
			rail(core, nil, rows, "shrink")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "hug", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "measured", 1, true) ~= nil).toBe(true)
	end)
end)
