--!strict
--[[
	MEASURED ITEM EXTENTS — `newVirtualList.itemExtent = "measured"` (Stage 2 of
	`docs/plans/variable-item-extents.md`).

	WHAT STAGE 1 LEFT, AND WHY IT WAS NOT ENOUGH. Stage 1 gave `itemExtent` a
	per-item FUNCTION form and moved every windowing number onto a running-offset
	index. That buys the expressive power to be correct per row — and the fixture
	written to demonstrate it got its own arithmetic wrong (a literal 1.25 line
	ratio; 372 findings on one node), because a DECLARED per-item extent is still a
	PREDICTION and predicting a row's height means hand-reproducing the solver's
	text arithmetic against four live facts. Stage 2 removes the prediction: the row
	is windowed at what it MEASURES.

	WHAT THIS SPEC PINS, and every one of these is a property the design could
	plausibly have lost:

	  · THE MEASUREMENT IS THE CELL'S OWN CONTENT, not the row's box. The row keeps
	    a fixed box (the index's number) so the canvas offsets and the painted rects
	    can never disagree; the cell rides a control-owned `Content` wrapper whose
	    main axis is `content`, so its arranged rect is its own measure whether the
	    row is currently too short or too tall for it. That is what makes
	    convergence ONE STEP: a measure that cannot see its own slot cannot chase
	    it.
	  · LAZINESS SURVIVES. Only WINDOWED rows are ever built, and therefore only
	    windowed rows are ever measured — proved with a build counter on a 10,000
	    row list, not a timer. The refused candidate design ("measure every item at
	    mount") cannot pass this, which is the whole reason it was refused.
	  · THE SCROLL DOES NOT JUMP as measurements land. Every measurement moves the
	    offset table under the player, which is the recorded jump class; the anchor
	    Stage 1 built for the accessibility case is what holds the content under the
	    eye, and this spec runs it on the measured path.
	  · A `fill` MAIN AXIS IS REFUSED, naming the row. Measured live: a `fill` cell
	    inside a content-sized wrapper measures ZERO, so the row would silently
	    collapse. The author's intent ("be as tall as my row") is circular here —
	    the row is as tall as the cell.
	  · THE LYING-EXTENT CLASS IS STRUCTURALLY CLOSED. The exact cell that makes the
	    solver's guard shout under a declared extent produces NO finding here.
	  · THE UNIFORM PATH IS UNTOUCHED. A measured list of equal rows converges to
	    the same geometry as the uniform list declaring that number.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local mountLib = require("../src/mount")
local fake_target = require("../tests/lib/fake_target")

local function makeRows(n: number): { { id: string, label: string } }
	local rows = {}
	for i = 1, n do
		table.insert(rows, { id = `r{i}`, label = `Row {i}` })
	end
	return rows
end

-- the headless stand-in for the engine moving CanvasPosition (the same one
-- `virtual_list_variable_extents.spec` uses): `scrollTo` echoes back through
-- every observer synchronously, exactly as `observeScroll` does.
local function scrollStub()
	local pos = { x = 0, y = 0 }
	local observers: { any } = {}
	local ctrl = {}
	function ctrl.observeScroll(_path: string, fn: any): () -> ()
		table.insert(observers, fn)
		return function() end
	end
	function ctrl.scrollTo(_path: string, p: { x: number, y: number })
		pos = { x = p.x, y = p.y }
		for _, fn in observers do
			fn(pos)
		end
	end
	function ctrl.lastPos()
		return pos
	end
	return ctrl
end

local function newList(core: any, opts: any)
	return virtual_list.build(Facet, core, {
		id = "VL",
		rows = opts.rows,
		key = function(item: any)
			return item.id
		end,
		axis = opts.axis,
		itemExtent = opts.itemExtent,
		estimatedItemExtent = opts.estimatedItemExtent,
		rowGap = opts.rowGap,
		viewportExtent = opts.viewportExtent or 498,
		overscan = opts.overscan or 2,
		cell = opts.cell or function(item: any)
			return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
	})
end

-- a PRESENTED list, so the real solver measures the cells and the presenter runs
-- the geometry broadcast that feeds the measurement back
local function world(opts: any)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local rows = core:signal(opts.rows or makeRows(8))
	local list = newList(core, {
		rows = rows,
		axis = opts.axis,
		itemExtent = opts.itemExtent or "measured",
		estimatedItemExtent = opts.estimatedItemExtent,
		rowGap = opts.rowGap,
		viewportExtent = opts.viewportExtent,
		overscan = opts.overscan,
		cell = opts.cell,
	})
	local screen = Facet.UI.Screen({ id = "S", children = { list.blueprint } })
	local handle = pres.present(screen)
	pres.refresh()
	local w: any = { core = core, list = list, rows = rows, adapter = adapter, handle = handle, pres = pres }
	function w.bind(): any
		local ctrl = scrollStub()
		list.bindNativeScroll(ctrl, `/S/VL`)
		return ctrl
	end
	function w.rowRect(key: string): any
		return handle.controller.rectOf(`/S/VL/Canvas/W/[{key}]/Row`)
	end
	function w.contentRect(key: string): any
		return handle.controller.rectOf(`/S/VL/Canvas/W/[{key}]/Row/Content`)
	end
	function w.dispose()
		list.dispose()
	end
	return w
end

-- a cell of `px` on the scroll axis, built from a plain Box so the number under
-- test is the fixture's and not the text engine's
local function plateCell(pxOf: (item: any) -> number, axis: string?)
	return function(item: any)
		local fixed: any = { type = "fixed", px = pxOf(item) }
		return Facet.UI.Box({
			id = "Plate",
			width = if axis == "x" then fixed else { type = "fill", weight = 1 },
			height = if axis == "x" then { type = "fill", weight = 1 } else fixed,
		})
	end
end

describe("VirtualList measured extents: what the spec accepts", function()
	it('accepts itemExtent = "measured" with an estimate, and the dump says so', function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(6))
		local list = newList(core, { rows = rows, itemExtent = "measured", estimatedItemExtent = 56 })
		local d = list.dump()
		expect(d.itemExtentMode).toBe("measured")
		-- there is no ONE extent, exactly as under a per-item function
		expect(d.itemExtent).toBe(nil)
		expect(d.rowHeight).toBe(nil)
		expect(d.estimatedItemExtent).toBe(56)
		-- nothing has been solved, so every row is still the estimate and the dump
		-- says how many of them are real measurements
		expect(d.measuredRows).toBe(0)
		expect(d.contentExtent).toBe(6 * 56)
		list.dispose()
	end)

	it("refuses measured mode with no estimate, and an estimate that is not a positive number", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(4))
		local function build(estimate: any)
			local list = newList(core, { rows = rows, itemExtent = "measured", estimatedItemExtent = estimate })
			list.dispose()
		end
		local ok, err = pcall(build, nil)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "estimatedItemExtent", 1, true) ~= nil).toBe(true)
		expect(pcall(build, 0)).toBe(false)
		expect(pcall(build, -3)).toBe(false)
		expect(pcall(build, "56")).toBe(false)
		expect(pcall(build, 56)).toBe(true)
	end)

	it("refuses an estimate on a list that does not measure — a field that drives nothing", function()
		--[[ Constitution §4's exact prohibition, and the rule
			`rowCapability.assertNarrowsSomething` already applies to the per-row
			opt-outs: an accepted property that does nothing is worse than a refused
			one, because the author believes it took effect. ]]
		local core = Facet.newCore()
		local rows = core:signal(makeRows(4))
		local ok, err = pcall(function()
			newList(core, { rows = rows, itemExtent = 56, estimatedItemExtent = 40 })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "estimatedItemExtent", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "measured", 1, true) ~= nil).toBe(true)
	end)

	it('refuses any other string: "measured" is the one word, not an open enum', function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(4))
		expect(pcall(function()
			newList(core, { rows = rows, itemExtent = "auto", estimatedItemExtent = 56 })
		end)).toBe(false)
	end)
end)

describe("VirtualList measured extents: the row is windowed at what it measures", function()
	it("a cell taller than the estimate moves the row's box AND the next row's offset", function()
		--[[ THE WHOLE FEATURE IN ONE CASE. Under a declared extent this list would
			window at 40 forever and every row would paint over its neighbour — the
			measured `row_actions` defect (84 declared, 88 measured at the DEFAULT text
			preference). Here the list learns 90 from the solve and re-windows. ]]
		local w = world({
			rows = makeRows(4),
			estimatedItemExtent = 40,
			viewportExtent = 600,
			cell = plateCell(function()
				return 90
			end),
		})
		w.pres.refresh()
		expect(w.contentRect("r1").h).toBe(90)
		expect(w.rowRect("r1").h).toBe(90)
		expect(w.rowRect("r2").y - w.rowRect("r1").y).toBe(90)
		expect(w.list.dump().contentExtent).toBe(4 * 90)
		expect(w.list.dump().measuredRows).toBe(4)
		w.dispose()
	end)

	it("rows of DIFFERENT measured heights each get their own slot", function()
		local w = world({
			rows = makeRows(4),
			estimatedItemExtent = 40,
			viewportExtent = 600,
			cell = plateCell(function(item: any)
				return ({ r1 = 30, r2 = 120, r3 = 60, r4 = 75 })[item.id] or 40
			end),
		})
		w.pres.refresh()
		expect(w.rowRect("r1").h).toBe(30)
		expect(w.rowRect("r2").h).toBe(120)
		expect(w.rowRect("r2").y - w.rowRect("r1").y).toBe(30)
		expect(w.rowRect("r3").y - w.rowRect("r1").y).toBe(150)
		expect(w.list.dump().contentExtent).toBe(30 + 120 + 60 + 75)
		w.dispose()
	end)

	it("the gutter is still dead space between measured slots", function()
		local w = world({
			rows = makeRows(3),
			estimatedItemExtent = 40,
			rowGap = 6,
			viewportExtent = 600,
			cell = plateCell(function()
				return 70
			end),
		})
		w.pres.refresh()
		local r1, r2 = w.rowRect("r1"), w.rowRect("r2")
		expect(r2.y - (r1.y + r1.h)).toBe(6)
		expect(w.list.dump().contentExtent).toBe(3 * 70 + 2 * 6)
		w.dispose()
	end)

	it('axis = "x" measures the item\'s WIDTH', function()
		local w = world({
			rows = makeRows(3),
			axis = "x",
			estimatedItemExtent = 40,
			viewportExtent = 600,
			cell = plateCell(function()
				return 110
			end, "x"),
		})
		w.pres.refresh()
		expect(w.rowRect("r1").w).toBe(110)
		expect(w.rowRect("r2").x - w.rowRect("r1").x).toBe(110)
		expect(w.list.dump().contentExtent).toBe(3 * 110)
		w.dispose()
	end)

	it("a row that SHRINKS is re-measured down, not ratcheted", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local rows = core:signal(makeRows(3))
		local px = core:signal(120)
		local list = newList(core, {
			rows = rows,
			itemExtent = "measured",
			estimatedItemExtent = 40,
			viewportExtent = 600,
			cell = function()
				return Facet.UI.Box({
					id = "Plate",
					width = { type = "fill", weight = 1 },
					height = core:memo(function(use)
						return { type = "fixed", px = use(px) }
					end),
				})
			end,
		})
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { list.blueprint } }))
		pres.refresh()
		expect(list.dump().contentExtent).toBe(3 * 120)
		px:set(48)
		pres.refresh()
		--[[ THE INDEX LEARNS IN THE SOLVE THAT MEASURED IT. `syncGeometry` runs from
			inside the solve's settle phase (L-31), so the write joins the flush that
			caused it rather than arriving a frame later.

			HOW MANY SOLVES THE ROW'S PAINTED BOX THEN TAKES IS DELIBERATELY NOT PINNED
			HERE. It is a property of the renderer's settle behaviour, not of this
			feature — measured at one solve on 2026-08-15, and it was two the same
			morning — and a test that fixed the number would redden every time somebody
			else made the framework converge faster. What this asserts is what a measured
			list actually promises: it converges, and then it holds still. ]]
		expect(list.dump().contentExtent).toBe(3 * 48)
		pres.refresh()
		expect(handle.controller.rectOf("/S/VL/Canvas/W/[r1]/Row").h).toBe(48)
		-- ...and it has SETTLED: nothing moves on any later solve, which is the half
		-- that would catch a re-measure chasing its own tail
		local settled = list.dump().measureEpoch
		pres.refresh()
		pres.refresh()
		expect(list.dump().measureEpoch).toBe(settled)
		expect(list.dump().contentExtent).toBe(3 * 48)
		expect(handle.controller.rectOf("/S/VL/Canvas/W/[r1]/Row").h).toBe(48)
		list.dispose()
	end)
end)

describe("VirtualList measured extents: what a measurement is allowed to be", function()
	it("a fractional measure is rounded to whole px, and a zero one is floored to 1", function()
		--[[ BOTH HALVES OF ONE LINE, and both were added on evidence rather than
			taste.

			WHOLE PX, because an extent is what the canvas and every offset are built
			from and sub-pixel measure noise is not a change: without the rounding a row
			whose content lands on 60.4 writes 60.4, and any solve that renders it a
			hair differently writes again — an invalidation, an index rebuild and a
			re-solve, every frame, forever. The declared path rounds for the same reason
			(the slot guard's own "sub-pixel measure noise is not a defect").

			FLOORED TO 1, because zero is not a legal slot. The running-offset index
			searches a prefix sum, and its `slotAt` predicate is only exact while the
			offsets strictly increase (`src/virtual_extents.luau`); a run of zero-extent
			rows makes several slots share one offset and the search can no longer tell
			them apart. A cell that measures 0 is also, in practice, a cell that has not
			painted yet — collapsing its row is the wrong answer to that too. ]]
		local w = world({
			rows = makeRows(3),
			estimatedItemExtent = 40,
			viewportExtent = 600,
			cell = plateCell(function()
				return 60.4
			end),
		})
		w.pres.refresh()
		expect(w.list.dump().contentExtent).toBe(3 * 60)
		w.dispose()

		local zero = world({
			rows = makeRows(3),
			estimatedItemExtent = 40,
			viewportExtent = 600,
			-- an empty stack: it measures nothing at all on either axis
			cell = function()
				return Facet.UI.VStack({ id = "Empty", padding = 0, gap = 0, children = {} })
			end,
		})
		zero.pres.refresh()
		expect(zero.list.dump().contentExtent).toBe(3)
		-- ...and the index still answers: a window over strictly-increasing offsets
		expect(#zero.list.dump().window > 0).toBe(true)
		zero.dispose()
	end)
end)

describe("VirtualList measured extents: laziness survives", function()
	it("only the WINDOWED rows are ever BUILT — 10,000 rows, counted", function()
		--[[ THE CHECK THAT KEEPS CANDIDATE 2 REFUSED, moved onto the measured path.
			"Measure every item at mount" would look identical in a screenshot and
			would delete the property the control exists for. A build counter, not a
			timer: the perf runner's own A/A control on these scenes measures a
			±5%..±28% band, which cannot resolve this and never could. ]]
		local core = Facet.newCore()
		local rows = core:signal(makeRows(10000))
		local built = 0
		local list = newList(core, {
			rows = rows,
			itemExtent = "measured",
			estimatedItemExtent = 56,
			viewportExtent = 498,
			cell = function(item: any)
				built += 1
				return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
		})
		local root = mountLib.mount(core, list.blueprint)
		expect(built < 30).toBe(true)
		local atTop = built
		list.scrollTop:set(300000)
		expect(built - atTop < 30).toBe(true)
		local mounted = 0
		for _ in list.debugWindow() do
			mounted += 1
		end
		expect(mounted < 20).toBe(true)
		root.dispose()
		list.dispose()
	end)

	it("rows the player has never reached keep the ESTIMATE, and the canvas says so", function()
		--[[ THE RESIDUAL COST candidate 1 always had, stated rather than hidden: the
			TOTAL content extent is an estimate until every row has been seen. The
			content under the eye is exact (that is what the anchor holds); the thumb's
			proportion is not. ]]
		local w = world({
			rows = makeRows(100),
			estimatedItemExtent = 40,
			viewportExtent = 200,
			overscan = 0,
			cell = plateCell(function()
				return 80
			end),
		})
		w.pres.refresh()
		local d = w.list.dump()
		-- only the window has been measured; the rest is still the estimate
		expect(d.measuredRows < 20).toBe(true)
		expect(d.measuredRows > 0).toBe(true)
		expect(d.contentExtent).toBe(d.measuredRows * 80 + (100 - d.measuredRows) * 40)
		w.dispose()
	end)

	it("convergence is ONE step: a second refresh over the same content writes nothing", function()
		--[[ A measure that cannot see its own slot cannot chase it — the cross axis
			is fixed by the viewport and the `Content` wrapper is sized by its own
			children, never by the row. Counted through the dump's own measurement
			epoch, so an implementation that re-wrote the same numbers every frame
			(and therefore re-solved the tree forever) reddens here. ]]
		local w = world({
			rows = makeRows(6),
			estimatedItemExtent = 40,
			viewportExtent = 300,
			cell = plateCell(function()
				return 77
			end),
		})
		w.pres.refresh()
		local settled = w.list.dump().measureEpoch
		w.pres.refresh()
		w.pres.refresh()
		expect(w.list.dump().measureEpoch).toBe(settled)
		w.dispose()
	end)
end)

describe("VirtualList measured extents: the scroll does not jump as measurements land", function()
	it("the item at the top of the viewport stays at the top when every row grows", function()
		--[[ THE ACCESSIBILITY CASE ON THE MEASURED PATH. Every cell grows at once
			because the player raised the text preference; every offset above the
			viewport grows with it. Without the anchor the player is somewhere else in
			their list — the recorded jump class. Stage 1 built the anchor for the
			DECLARED path; this is it running on measurements. ]]
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, Facet.newActionSystem(core))
		local rows = core:signal(makeRows(200))
		local px = core:signal(56)
		local list = newList(core, {
			rows = rows,
			itemExtent = "measured",
			estimatedItemExtent = 56,
			viewportExtent = 400,
			cell = function()
				return Facet.UI.Box({
					id = "Plate",
					width = { type = "fill", weight = 1 },
					height = core:memo(function(use)
						return { type = "fixed", px = use(px) }
					end),
				})
			end,
		})
		local handle = pres.present(Facet.UI.Screen({ id = "S", children = { list.blueprint } }))
		pres.refresh()
		local ctrl = scrollStub()
		list.bindNativeScroll(ctrl, "/S/VL")
		-- park 10px into row 21, with every row so far measured at 56
		ctrl.scrollTo("/S/VL", { x = 0, y = 20 * 56 + 10 })
		pres.refresh()
		pres.refresh()
		expect(list.dump().window[3]).toBe("r21")
		--[[ THE ASSERTION IS THE INVARIANT, NOT A PIXEL, and the first draft of this
			test got that wrong in a way worth recording: it expected `20 * 84 + 10`,
			which is where row 21 would start if every row above it had been measured.
			They have not been — that is the LAZINESS this design refuses to give up —
			so rows outside the window are still the estimate and the absolute canvas
			offset is a mix. The property the player feels is "the row under the top
			edge is still the row under the top edge, at the same offset into it", and
			that is what is asserted: the distance from the scroll to row 21's own
			leading edge does not move when every row grows by half again. ]]
		--[[ ...AND BOTH SIDES ARE RELATIVE TO THE CANVAS. `scrollTop` is a canvas
			offset and a rect is in the surface's own space, so the two were only
			comparable while the canvas sat at y = 0 — which it did until every content
			policy gained its gutter floor (ADR-0040 §B-24). ]]
		local function offsetIntoAnchor(): number
			local rect = handle.controller.rectOf("/S/VL/Canvas/W/[r21]/Row")
			local canvas = handle.controller.rectOf("/S/VL/Canvas")
			assert(rect ~= nil and canvas ~= nil, "r21 is not mounted")
			return list.dump().scrollTop - (rect.y - canvas.y)
		end
		expect(offsetIntoAnchor()).toBe(10)
		-- the preference moves: every mounted row measures 84 now
		px:set(84)
		pres.refresh()
		pres.refresh()
		expect(list.dump().window[3]).toBe("r21")
		expect(offsetIntoAnchor()).toBe(10)
		--[[ ...AND THE CONTROL THAT MAKES THAT MEAN SOMETHING. Without the anchor the
			scroll would be exactly where it was left while the offsets under it grew,
			so the offset into row 21 would be a different number. It is not, and the
			scroll DID move — proving the correction ran rather than nothing happening. ]]
		expect(list.dump().scrollTop ~= 20 * 56 + 10).toBe(true)
		list.dispose()
	end)
end)

describe("VirtualList measured extents: a fill main axis is refused", function()
	it("a cell that declares fill on the SCROLL axis is refused, naming the row", function()
		--[[ MEASURED LIVE, and it is why this is an error rather than a degrade: a
			`fill` child inside a content-sized wrapper measures ZERO, so the row would
			collapse to nothing and no number in any dump would say why. The intent is
			circular in measured mode — the row is as tall as the cell, so a cell that
			asks to be as tall as the row is asking to be as tall as itself. ]]
		local core = Facet.newCore()
		local rows = core:signal(makeRows(3))
		local ok, err = pcall(function()
			local list = newList(core, {
				rows = rows,
				itemExtent = "measured",
				estimatedItemExtent = 56,
				cell = function()
					return Facet.UI.Box({
						id = "Plate",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
					})
				end,
			})
			mountLib.mount(core, list.blueprint)
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "fill", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "r1", 1, true) ~= nil).toBe(true)
	end)

	it("fill on the CROSS axis is fine — that is how a row spans the list", function()
		local w = world({
			rows = makeRows(3),
			estimatedItemExtent = 40,
			viewportExtent = 300,
			cell = plateCell(function()
				return 64
			end),
		})
		w.pres.refresh()
		expect(w.rowRect("r1").h).toBe(64)
		w.dispose()
	end)

	it("a DECLARED list still accepts a fill cell — the refusal is measured mode's", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(3))
		local ok = pcall(function()
			local list = newList(core, {
				rows = rows,
				itemExtent = 56,
				cell = function()
					return Facet.UI.Box({
						id = "Plate",
						width = { type = "fill", weight = 1 },
						height = { type = "fill", weight = 1 },
					})
				end,
			})
			mountLib.mount(core, list.blueprint)
		end)
		expect(ok).toBe(true)
	end)
end)

describe("VirtualList measured extents: the lying-extent class is structurally closed", function()
	it("the cell that makes the guard shout under a DECLARATION produces no finding here", function()
		--[[ The differential that says this is a fix and not a coincidence. The same
			60px plate in a list that DECLARES 20 is the guard's own case (it is pinned
			in `virtual_list_variable_extents.spec`); measured, there is no declaration
			left to be wrong. ]]
		local w = world({
			rows = makeRows(3),
			estimatedItemExtent = 20,
			viewportExtent = 600,
			cell = plateCell(function()
				return 60
			end),
		})
		--[[ TWO SOLVES, AND THE SECOND IS NOT A CHEAT. The first solve is the one the
			estimate is still in force for, and a row painting past a box that is about
			to grow IS worth a finding while it is true — the sweep's own surfaces are
			read after they have settled. What this pins is that nothing SURVIVES the
			convergence: under a declared extent this exact cell files forever. ]]
		w.pres.refresh()
		w.pres.refresh()
		for _, d in w.handle.controller.diagnostics() do
			expect(string.find(d.issue, "itemExtent", 1, true)).toBe(nil)
			expect(string.find(d.issue, "overflows its zstack", 1, true)).toBe(nil)
		end
		w.dispose()
	end)
end)

describe("VirtualList measured extents: the data is the cache's boundary", function()
	it("a removed row's measurement is dropped with it", function()
		local w = world({
			rows = makeRows(4),
			estimatedItemExtent = 40,
			viewportExtent = 600,
			cell = plateCell(function()
				return 70
			end),
		})
		w.pres.refresh()
		expect(w.list.dump().measuredRows).toBe(4)
		w.rows:set(makeRows(2))
		w.pres.refresh()
		expect(w.list.dump().measuredRows).toBe(2)
		expect(w.list.dump().contentExtent).toBe(2 * 70)
		w.dispose()
	end)
end)

describe("VirtualList measured extents: the uniform path is untouched", function()
	it("a measured list of EQUAL rows converges to the uniform list declaring that number", function()
		--[[ THE DIFFERENTIAL ORACLE, one level up from Stage 1's. Two lists, same
			data, same viewport, same gap: one declares `itemExtent = 64`, the other
			measures cells that are 64. Once converged, every observable has to agree —
			or the general mechanism does not contain the special case it replaces. ]]
		local declared = world({
			rows = makeRows(40),
			itemExtent = 64,
			rowGap = 6,
			viewportExtent = 300,
			cell = plateCell(function()
				return 64
			end),
		})
		local measured = world({
			rows = makeRows(40),
			estimatedItemExtent = 64,
			rowGap = 6,
			viewportExtent = 300,
			cell = plateCell(function()
				return 64
			end),
		})
		measured.pres.refresh()
		for _, top in { 0, 70, 700, 1400, 100000 } do
			declared.list.scrollTop:set(top)
			measured.list.scrollTop:set(top)
			declared.pres.refresh()
			measured.pres.refresh()
			local u, v = declared.list.dump(), measured.list.dump()
			expect(v.scrollTop).toBe(u.scrollTop)
			expect(v.contentExtent).toBe(u.contentExtent)
			-- the measured window is the variable rule, which is a strict SUPERSET of
			-- the uniform one at a fractional offset and identical at a slot boundary
			expect(v.window[1]).toBe(u.window[1])
			expect(#v.window >= #u.window).toBe(true)
			expect(#v.window - #u.window <= 1).toBe(true)
		end
		declared.list.scrollTop:set(0)
		measured.list.scrollTop:set(0)
		declared.pres.refresh()
		measured.pres.refresh()
		for _, key in { "r1", "r2", "r3" } do
			local a, b = declared.rowRect(key), measured.rowRect(key)
			expect(`{b.y}|{b.h}`).toBe(`{a.y}|{a.h}`)
		end
		declared.dispose()
		measured.dispose()
	end)
end)
