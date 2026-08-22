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
	local paneDim = w.core:memo(function(use)
		return { type = "fixed", px = use(paneMain) }
	end)
	w.present(Facet.UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			Facet.UI.VStack({
				id = "Pane",
				padding = 0,
				gap = 0,
				-- the pane is FIXED on y and FILLS on x, so a vertical list's SCROLL
				-- axis and a horizontal rail's CROSS axis are both the number under
				-- test, and neither is the screen's
				width = { type = "fill", weight = 1 },
				height = paneDim,
				children = { built.blueprint },
			}),
		},
	}))
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
