--!strict
--[[
	THE LAZY GRID — `newVirtualGrid`, the lazy grid ([SW-21]).

	THE GAP THIS CLOSES (the comparison document §4.2, the
	a sideways grid/a vertical grid row). Facet shipped only the EAGER half of the grid:
	`UI.Grid` measures and arranges every cell, and an eager grid says
	the same of itself — it "renders all of its child views immediately"
	([SW-16]). The lazy grids are the ones that "create items only as needed"
	([SW-21]), and nothing in Facet did.

	WHAT THIS SPEC PINS:

	  · THE INDEX IS USED AS-IS, IN LINE UNITS. `src/virtual_extents.luau` is the
	    one windowing arithmetic in this framework and it did not have to change:
	    a grid windows by LINE OF CELLS instead of by item, which is the same
	    prefix sum over a different unit. The cell<->line mapping is division, not
	    windowing. Proved here by a DIFFERENTIAL against the module itself, so the
	    grid cannot drift into a second arithmetic that merely agrees today;

	  · THE MOUNTED BAND IS A REAL `UI.Grid`, so the column arithmetic is the
	    shipped one — `floor((innerW - gap * (lanes - 1)) / lanes)` — not a copy
	    of it. Proved by a differential against a plain `UI.Grid` of the same
	    width, including the SHORT LAST LINE, which must keep its column width
	    rather than stretch;

	  · LAZINESS IS REAL, and the check is a BUILD COUNTER, not a timer. It is
	    two-sided on purpose: an EXACT count, so "mount nothing" fails it exactly
	    as "mount everything" does. The stronger form is here too — the build
	    count is INDEPENDENT OF N (100 items and 10 000 items build the same
	    cells), which is the property "only as needed" actually names;

	  · SCROLL POSITION STAYS STABLE, on both of a grid's destabilizers: the line
	    extents re-deriving (the accessibility case `newVirtualList` already
	    guards) and the COLUMN COUNT changing (the reflow case, which is a grid's
	    own and which moves every item to a different line). One anchor covers
	    both because it anchors on the ITEM, not on the line.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local virtual_grid = require("../src/controls/virtual_grid")
local mountLib = require("../src/mount")
local fake_target = require("../tests/lib/fake_target")
local virtual_extents = require("../src/virtual_extents") :: any

local function makeItems(n: number): { { id: string, label: string } }
	local items = table.create(n)
	for i = 1, n do
		items[i] = { id = `i{i}`, label = `Item {i}` }
	end
	return items
end

-- the headless stand-in for the engine moving CanvasPosition: `scrollTo` echoes
-- back through every observer synchronously, exactly as `observeScroll` does.
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

local function newGrid(core: any, opts: any)
	return virtual_grid.build(Facet, core, {
		id = opts.id or "VG",
		items = opts.items,
		key = function(item: any)
			return item.id
		end,
		axis = opts.axis,
		columns = opts.columns,
		itemExtent = opts.itemExtent or 40,
		rowGap = opts.rowGap,
		gap = opts.gap,
		viewportExtent = opts.viewportExtent or 200,
		overscan = opts.overscan,
		width = opts.width,
		cell = opts.cell or function(item: any)
			return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
	})
end

-- a PRESENTED grid, so the real solver gives rects to measure cells against
local function world(opts: any)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local items = core:signal(opts.items or makeItems(20))
	local grid = newGrid(core, {
		items = items,
		columns = opts.columns or 4,
		itemExtent = opts.itemExtent,
		rowGap = opts.rowGap,
		gap = opts.gap,
		viewportExtent = opts.viewportExtent,
		overscan = opts.overscan,
		width = opts.width or { type = "fixed", px = 320 },
		cell = opts.cell,
	})
	local screen = Facet.UI.Screen({ id = "S", padding = 0, gap = 0, children = { grid.blueprint } })
	local handle = pres.present(screen)
	pres.refresh()
	grid.bindNativeScroll(handle.controller)
	local w: any = { core = core, grid = grid, items = items, handle = handle, pres = pres }
	function w.cellRect(key: string): any
		return handle.controller.rectOf(`/S/VG/Canvas/Band/W/[{key}]/Cell`)
	end
	function w.rect(path: string): any
		return handle.controller.rectOf(path)
	end
	return w
end

--[[ ── A. WHAT THE SPEC ACCEPTS, AND WHAT IT REFUSES AT CONSTRUCTION ────────── ]]

describe("VirtualGrid: what the spec accepts", function()
	it("an unknown spec key is refused and the message names it", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			virtual_grid.build(Facet, core, {
				id = "VG",
				items = core:signal({}),
				key = function(i: any)
					return i.id
				end,
				columns = 3,
				itemExtent = 40,
				viewportExtent = 200,
				cell = function()
					return Facet.UI.Text({ id = "L", text = "x" })
				end,
				minColumWidth = 120,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "minColumWidth", 1, true) ~= nil).toBe(true)
	end)

	it("columns must be a positive INTEGER — 0, a fraction and a negative are all refused", function()
		local core = Facet.newCore()
		local items = core:signal(makeItems(4))
		for _, bad in { 0, 2.5, -3 } do
			local ok, err = pcall(newGrid, core, { items = items, columns = bad })
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "columns", 1, true) ~= nil).toBe(true)
		end
		-- ...and the legal one still builds
		local grid = newGrid(core, { items = items, columns = 3 })
		expect(grid.dump().lanes).toBe(3)
		grid.dispose()
	end)

	it("itemExtent must be a positive number, a Readable, or a per-LINE function", function()
		local core = Facet.newCore()
		local items = core:signal(makeItems(4))
		local ok, err = pcall(newGrid, core, { items = items, columns = 2, itemExtent = "tall" })
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "itemExtent", 1, true) ~= nil).toBe(true)
		-- all three legal forms build, and the mode is visible in the dump
		expect(newGrid(core, { items = items, columns = 2, itemExtent = 40 }).dump().itemExtentMode).toBe("uniform")
		expect(newGrid(core, { items = items, columns = 2, itemExtent = core:signal(40) }).dump().itemExtentMode).toBe(
			"uniform"
		)
		expect(newGrid(core, {
			items = items,
			columns = 2,
			itemExtent = function()
				return 40
			end,
		}).dump().itemExtentMode).toBe("variable")
	end)

	--[[ `axis = "x"` USED TO BE REFUSED HERE, and the refusal named its own
		prerequisite: `UI.Grid` wrapped row-major only, so a horizontal grid had no
		lane mechanism to inherit. That prerequisite shipped (`flow = "column"`,
		`tests/grid_column_flow.spec.luau`) and the axis with it —
		`tests/virtual_hgrid.spec.luau` is the sideways half. What is still refused
		is an axis that is not an axis, and the message names the legal pair. ]]
	it('axis = "x" is accepted; an axis that is not an axis is refused', function()
		local core = Facet.newCore()
		local sideways = newGrid(core, { items = core:signal(makeItems(9)), columns = 3, axis = "x" })
		expect(sideways.dump().axis).toBe("x")
		sideways.dispose()
		local upright = newGrid(core, { items = core:signal(makeItems(9)), columns = 3 })
		expect(upright.dump().axis).toBe("y") -- the default, unchanged
		upright.dispose()
		local ok, err = pcall(newGrid, core, { items = core:signal(makeItems(4)), columns = 2, axis = "z" })
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "axis", 1, true) ~= nil).toBe(true)
	end)

	it("a per-line itemExtent that returns garbage fails at CONSTRUCTION, naming the line", function()
		local core = Facet.newCore()
		local ok, err = pcall(newGrid, core, {
			items = core:signal(makeItems(9)),
			columns = 3,
			itemExtent = function(line: number)
				return if line == 2 then -1 else 40
			end,
		})
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "itemExtent", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "line 2", 1, true) ~= nil).toBe(true)
	end)
end)

--[[ ── B. THE RUNNING-OFFSET INDEX, USED AS-IS, IN LINE UNITS ───────────────── ]]

describe("VirtualGrid: the extent index is the shipped one, its unit is a LINE", function()
	it("the canvas extent IS virtual_extents.uniform over ceil(N / lanes) lines — a differential", function()
		--[[ THE POINT OF THIS CASE. A grid could have grown its own "sum the lines"
			loop that happens to agree with the module today. Comparing against the
			module itself is what makes the two unable to drift: if the grid ever
			re-derives content, this reddens on the first disagreement. ]]
		local core = Facet.newCore()
		local grid = newGrid(core, { items = core:signal(makeItems(17)), columns = 4, itemExtent = 40, rowGap = 6 })
		-- 17 items over 4 lanes is 5 lines: four full and one of a single cell
		local ix = virtual_extents.uniform(5, 40, 6)
		expect(grid.dump().lineCount).toBe(5)
		expect(grid.dump().content).toBe(ix.content)
		expect(grid.dump().content).toBe(5 * 40 + 4 * 6)
		grid.dispose()
	end)

	it("the WINDOW is the index's window in line units, and the items follow by division", function()
		local core = Facet.newCore()
		local grid = newGrid(core, {
			items = core:signal(makeItems(400)),
			columns = 4,
			itemExtent = 40,
			rowGap = 6,
			viewportExtent = 200,
			overscan = 0,
		})
		local ix = virtual_extents.uniform(100, 40, 6)
		grid.scrollTop:set(460)
		local first, last = ix.window(460, 200, 0)
		expect(grid.dump().lines).toEqual({ first, last })
		-- ...and the mounted items are exactly the cells of those lines
		local expected = {}
		for line = first, last do
			for lane = 1, 4 do
				table.insert(expected, `i{(line - 1) * 4 + lane}`)
			end
		end
		expect(grid.dump().window).toEqual(expected)
		grid.dispose()
	end)

	it("a viewport inside ONE tall line windows that line alone (the prefix sum, searched)", function()
		local core = Facet.newCore()
		-- lines of 40, 249, 40, 120 — the ragged shape the extent ruling names
		local RAGGED = { 40, 249, 40, 120 }
		local grid = newGrid(core, {
			items = core:signal(makeItems(80)),
			columns = 4,
			overscan = 0,
			viewportExtent = 120,
			itemExtent = function(line: number)
				return RAGGED[(line - 1) % #RAGGED + 1]
			end,
		})
		-- line 2 spans 40..289; a 120px viewport parked at 60 is entirely inside it
		grid.scrollTop:set(60)
		expect(grid.dump().lines).toEqual({ 2, 2 })
		expect(grid.dump().window).toEqual({ "i5", "i6", "i7", "i8" })
		grid.dispose()
	end)

	it("the LAST line is short, and the index still spans exactly the lines that exist", function()
		local core = Facet.newCore()
		local grid = newGrid(core, { items = core:signal(makeItems(9)), columns = 4, itemExtent = 40, rowGap = 6 })
		-- 9 items over 4 lanes is 3 lines, the last holding ONE cell
		expect(grid.dump().lineCount).toBe(3)
		expect(grid.dump().content).toBe(3 * 40 + 2 * 6)
		expect(grid.dump().window).toEqual({ "i1", "i2", "i3", "i4", "i5", "i6", "i7", "i8", "i9" })
		grid.dispose()
	end)
end)

--[[ ── C. LAZINESS IS REAL — THE BUILD COUNTER ──────────────────────────────── ]]

describe("VirtualGrid: only the windowed cells are ever built", function()
	it("10 000 items, 4 lanes: the EXACT cells of the windowed lines are built and no others", function()
		--[[ THE PROPERTY THE WHOLE CONSTRUCT IS ABOUT, and the check that keeps it.
			A BUILD COUNTER, not a timer — and an EXACT count rather than a ceiling,
			because "<= 40" is also satisfied by mounting nothing, which is a lazy
			grid that has deleted itself. Both directions are named here. ]]
		local core = Facet.newCore()
		local built = 0
		local grid = newGrid(core, {
			items = core:signal(makeItems(10000)),
			columns = 4,
			itemExtent = 40,
			viewportExtent = 200,
			overscan = 2,
			cell = function(item: any)
				built += 1
				return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
		})
		local root = mountLib.mount(core, grid.blueprint)
		-- 10 000 items over 4 lanes is 2 500 lines. At the top, a 200px viewport of
		-- 40px lines touches lines 1..5, plus 2 lines of overscan below (there is
		-- nothing above) = lines 1..7 = 28 cells. NOT "at most 28".
		expect(grid.dump().lines).toEqual({ 1, 7 })
		expect(built).toBe(28)
		expect(#grid.dump().window).toBe(28)

		-- a deep jump windows a NEW band and builds only that band — not the 60 000
		-- cells it flew past
		local atTop = built
		grid.scrollTop:set(24000)
		expect(built - atTop).toBe(36) -- lines 599..607: 9 lines x 4 lanes
		expect(#grid.dump().window).toBe(36)
		root.dispose()
		grid.dispose()
	end)

	it("the build count does not depend on N — 100 items and 10 000 build the same cells", function()
		--[[ "CREATE ITEMS ONLY AS NEEDED" ([SW-21]) IS A STATEMENT ABOUT N. A count
			that is bounded but grows with the collection is not laziness, it is a
			smaller eager grid. This is the differential that says so. ]]
		local function buildsFor(n: number): number
			local core = Facet.newCore()
			local built = 0
			local grid = newGrid(core, {
				items = core:signal(makeItems(n)),
				columns = 4,
				itemExtent = 40,
				viewportExtent = 200,
				overscan = 2,
				cell = function(item: any)
					built += 1
					return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
				end,
			})
			local root = mountLib.mount(core, grid.blueprint)
			root.dispose()
			grid.dispose()
			return built
		end
		expect(buildsFor(10000)).toBe(buildsFor(100))
		expect(buildsFor(10000)).toBe(28)
	end)

	it("a per-line extent function is ARITHMETIC over every line and builds nothing", function()
		--[[ The line the refused "measure every item at mount" candidate crosses and
			this one does not: the extent function runs O(lines) times per data
			change — no cell is built and nothing is measured.

			THE COUNT IS 32 HERE AND 28 ON THE UNIFORM PATH, AND THAT IS THE RECORDED
			DIVERGENCE, NOT A DEFECT. `docs/plans/variable-item-extents.md` states it:
			the uniform rule takes the visible COUNT from the viewport alone
			(`ceil(200 / 40) = 5` lines), which is independent of where between two
			lines the scroll sits; the variable rule cannot take a count — with ragged
			extents "how many lines fit in 200px" has no answer — so it asks which
			line holds the viewport's TRAILING edge, and 200 lands on line 6's leading
			edge. One extra line each side of the same 4 lanes. It is a strict
			SUPERSET, never a subset, so no cell the viewport touches goes unmounted;
			both halves are asserted below so the relationship is pinned and not just
			the number. ]]
		local core = Facet.newCore()
		local extentCalls = 0
		local built = 0
		local grid = newGrid(core, {
			items = core:signal(makeItems(10000)),
			columns = 4,
			viewportExtent = 200,
			overscan = 2,
			itemExtent = function()
				extentCalls += 1
				return 40
			end,
			cell = function(item: any)
				built += 1
				return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
		})
		local root = mountLib.mount(core, grid.blueprint)
		expect(extentCalls >= 2500).toBe(true) -- every LINE, at least once
		expect(built).toBe(32) -- and still only the window is BUILT
		expect(grid.dump().lines).toEqual({ 1, 8 })
		-- the superset relationship itself: the variable window CONTAINS the uniform
		-- one at this offset, which is what makes the extra line safe in kind
		local uniform = virtual_extents.uniform(2500, 40, 0)
		local uFirst, uLast = uniform.window(0, 200, 2)
		expect(grid.dump().lines[1] <= uFirst).toBe(true)
		expect(grid.dump().lines[2] >= uLast).toBe(true)
		root.dispose()
		grid.dispose()
	end)
end)

--[[ ── D. SCROLL POSITION STAYS STABLE ──────────────────────────────────────── ]]

describe("VirtualGrid: the scroll does not jump", function()
	it("when the line extents re-derive, the item at the top of the viewport stays at the top", function()
		local core = Facet.newCore()
		local grow = core:signal(0)
		local grid = newGrid(core, {
			items = core:signal(makeItems(400)),
			columns = 4,
			viewportExtent = 200,
			itemExtent = function(_line: number, use: any): number
				return 40 + use(grow)
			end,
		})
		local ctrl = scrollStub()
		grid.bindNativeScroll(ctrl, "/VG")
		-- park line 11 (items i41..i44) at the top, 10px in
		ctrl.scrollTo("/VG", { x = 0, y = 10 * 40 + 10 })
		expect(grid.dump().anchorKey).toBe("i41")
		-- the preference moves: every line is 28px taller
		grow:set(28)
		expect(ctrl.lastPos().y).toBe(10 * 68 + 10)
		expect(grid.dump().scrollTop).toBe(10 * 68 + 10)
		grid.dispose()
	end)

	--[[ THE END-OF-GRID SHRINK, ported from `controls/table.luau` with its fix
		(reuse audit 2026-08-17). The anchor observer compared its target against
		`clampedTop` — a MEMO over the index — instead of against `scrollTop`, the
		raw engine mirror. Hard against the end of a grid whose lines then SHRINK,
		the memo has already clamped itself to the new maximum while the engine's
		real `CanvasPosition` is still far past the last line, so the two agree,
		nothing is written, and the player is left looking at blank space. Measured
		on the Table at 400 rows shrinking 43 -> 40px: 1,200px out of range. ]]
	it("shrinking the lines at the END still corrects the ENGINE, not just the memo", function()
		local core = Facet.newCore()
		local grow = core:signal(28)
		local grid = newGrid(core, {
			items = core:signal(makeItems(400)),
			columns = 4,
			viewportExtent = 200,
			itemExtent = function(_line: number, use: any): number
				return 40 + use(grow)
			end,
		})
		local ctrl = scrollStub()
		grid.bindNativeScroll(ctrl, "/VG")
		-- hard against the end: 100 lines at 68px, a 200px viewport
		local content = 100 * 68
		ctrl.scrollTo("/VG", { x = 0, y = content - 200 })
		expect(grid.dump().scrollTop).toBe(content - 200)

		-- every line shrinks back to 40px: the content is 4,000 and the engine is
		-- 2,600px past the end of it
		grow:set(0)
		local corrected = ctrl.lastPos().y
		expect(corrected <= 100 * 40 - 200 + 0.5).toBe(true)
		expect(corrected < content - 200).toBe(true)
		grid.dispose()
	end)

	it("when the COLUMN COUNT changes, the item at the top of the viewport stays at the top", function()
		--[[ A GRID'S OWN DESTABILIZER, and the reason the anchor is on the ITEM
			rather than on the line. A reflow moves every item to a different line,
			so a line-keyed anchor would hold a line the player was never looking
			at. `newVirtualList` never had this case: there, an item IS its line. ]]
		local core = Facet.newCore()
		local lanes = core:signal(4)
		local grid = newGrid(core, {
			items = core:signal(makeItems(400)),
			columns = lanes,
			itemExtent = 40,
			viewportExtent = 200,
		})
		local ctrl = scrollStub()
		grid.bindNativeScroll(ctrl, "/VG")
		-- park line 11 at the top: items i41..i44, so i41 is the anchor
		ctrl.scrollTo("/VG", { x = 0, y = 400 })
		expect(grid.dump().anchorKey).toBe("i41")
		-- the pane narrows to 2 columns: i41 is now the first cell of line 21
		lanes:set(2)
		expect(grid.dump().lanes).toBe(2)
		expect(ctrl.lastPos().y).toBe(20 * 40)
		expect(grid.dump().window[1]).toBe("i37") -- two lines of overscan above
		grid.dispose()
	end)
end)

--[[ ── E. THE MOUNTED BAND IS A REAL `UI.Grid` ──────────────────────────────── ]]

describe("VirtualGrid: the column arithmetic is the shipped one, not a copy", function()
	it("cell width equals a plain UI.Grid's column at the same width, gap and count", function()
		--[[ THE DIFFERENTIAL THAT FORBIDS A SECOND ARITHMETIC. The band a
			VirtualGrid mounts IS a `UI.Grid`, so this is not "the two agree" — it is
			"there is one of them". A change to the flow grid's column rule moves
			both sides of this case together, which is the point. ]]
		local w = world({
			items = makeItems(12),
			columns = 4,
			gap = 4,
			itemExtent = 40,
			width = { type = "fixed", px = 320 },
		})
		-- floor((320 - 4 * 3) / 4) = 77, the flow grid's own formula; the xs start at
		-- the content rect's own 8px gutter (ADR-0040 §B-24)
		expect(w.cellRect("i1").w).toBe(77)
		expect(w.cellRect("i1").x).toBe(8)
		expect(w.cellRect("i2").x).toBe(89)
		expect(w.cellRect("i4").x).toBe(251)
		w.grid.dispose()
	end)

	it("a SHORT last line keeps its column width and stays left-aligned", function()
		local w =
			world({ items = makeItems(6), columns = 4, gap = 4, itemExtent = 40, width = { type = "fixed", px = 320 } })
		-- line 2 holds two cells; they must be 77 wide at the content gutter and 81
		-- past it, NOT stretched
		expect(w.cellRect("i5").w).toBe(77)
		expect(w.cellRect("i5").x).toBe(8)
		expect(w.cellRect("i6").x).toBe(89)
		expect(w.cellRect("i6").w).toBe(77)
		w.grid.dispose()
	end)

	it("each mounted cell is exactly its own LINE's extent tall, and the lines stack at the index's offsets", function()
		--[[ FOUND BY MUTATION, AND THE HOLE IS WORTH NAMING. Every other layout case
			in this file uses a 40px line, so pinning the cell's height to a LITERAL 40
			passed all of them — a cell that ignores its line's extent entirely was
			invisible. The flow grid takes each line's height from its tallest cell, so
			this pin is what makes the band's own geometry equal the geometry the index
			already committed to; ragged extents are the only shape that can see it. ]]
		local RAGGED = { 40, 249, 40, 120 }
		local w = world({
			items = makeItems(16),
			columns = 4,
			overscan = 2,
			viewportExtent = 200,
			itemExtent = function(line: number)
				return RAGGED[(line - 1) % #RAGGED + 1]
			end,
		})
		local canvasY = w.rect("/S/VG/Canvas").y
		expect(w.cellRect("i1").h).toBe(40)
		expect(w.cellRect("i5").h).toBe(249)
		expect(w.cellRect("i9").h).toBe(40)
		expect(w.cellRect("i13").h).toBe(120)
		-- ...and they stack at the running-offset index's own offsets
		expect(w.cellRect("i1").y - canvasY).toBe(0)
		expect(w.cellRect("i5").y - canvasY).toBe(40)
		expect(w.cellRect("i9").y - canvasY).toBe(40 + 249)
		expect(w.cellRect("i13").y - canvasY).toBe(40 + 249 + 40)
		w.grid.dispose()
	end)

	it("the canvas is the FULL virtual extent and the band sits at its line's offset", function()
		local w = world({
			items = makeItems(400),
			columns = 4,
			itemExtent = 40,
			rowGap = 6,
			viewportExtent = 200,
			overscan = 0,
		})
		expect(w.rect("/S/VG/Canvas").h).toBe(100 * 40 + 99 * 6)
		w.grid.scrollTop:set(460)
		w.pres.refresh()
		local first = w.grid.dump().lines[1]
		-- ...from the content rect's own gutter, which is where the canvas starts
		expect(w.rect("/S/VG/Canvas/Band").y).toBe(8 + (first - 1) * 46)
		w.grid.dispose()
	end)
end)

--[[ ── F. THE NATIVE SCROLL SUBSTRATE ───────────────────────────────────────── ]]

describe("VirtualGrid: the engine owns the offset, the framework owns the window", function()
	it("the engine's reported offset moves the window", function()
		local core = Facet.newCore()
		local grid = newGrid(core, {
			items = core:signal(makeItems(400)),
			columns = 4,
			itemExtent = 40,
			viewportExtent = 200,
			overscan = 0,
		})
		local ctrl = scrollStub()
		grid.bindNativeScroll(ctrl, "/VG")
		expect(grid.dump().lines).toEqual({ 1, 5 })
		ctrl.scrollTo("/VG", { x = 0, y = 800 })
		expect(grid.dump().lines).toEqual({ 21, 25 })
		grid.dispose()
	end)

	it("revealItem reaches an item that has no path at all, and returns the path it gains", function()
		local w = world({ items = makeItems(400), columns = 4, itemExtent = 40, viewportExtent = 200 })
		expect(w.cellRect("i200")).toBe(nil)
		local path = w.grid.revealItem("i200")
		w.pres.refresh()
		expect(path).toBe("/S/VG/Canvas/Band/W/[i200]/Cell")
		expect(w.cellRect("i200") ~= nil).toBe(true)
		w.grid.dispose()
	end)
end)

--[[ ── D. AN OFF-WINDOW EDIT THAT MOVES NOTHING MUST DIRTY NOTHING ─────────── ]]

describe("VirtualGrid: the canvas Dim is compared by VALUE (review RR-5)", function()
	it("an off-window edit that changes no key and no extent dirties NOTHING", function()
		--[[ THE SAME CONSTRUCT, THE SAME QUESTION, ASKED OF THE GRID.

			`newVirtualList`'s canvas Dim (`src/controls/virtual_window.luau`) was the
			one memo the T15 measurement caught costing a real re-solve: it is
			`{ type = "fixed", px = index.content }`, a table literal is never
			identity-equal to the one before it, and so a list whose LENGTH did not
			change re-published the same number and the surface re-solved. The grid
			declares the identical memo in the identical role, and no perf scene or lab
			workload mounts a grid — so the measurement that fixed the list could not
			see this one at all. A churn-counter case IS the measurement.

			Read it as two-sided. Nothing about the edit can move: item 200 of 400 is
			far outside the mounted band, the key is the same, and the count is the
			same so the canvas extent is the number it already was. If a future change
			buys the arrange back by making the window deaf to a real edit, the
			laziness cases above are what fail. ]]
		local core = Facet.newCore()
		local items = makeItems(400)
		local signal = core:signal(items)
		local grid = newGrid(core, {
			items = signal,
			columns = 4,
			itemExtent = 40,
			viewportExtent = 200,
			overscan = 2,
		})
		local root = mountLib.mount(core, grid.blueprint)
		root.takeDirty()

		local next = table.clone(items)
		next[200] = { id = "i200", label = "Item 200 (edited off-window)" }
		signal:set(next)

		local dirty: { string } = {}
		for _, entry in root.takeDirty() do
			table.insert(dirty, entry.class)
		end
		expect(table.concat(dirty, ",")).toBe("")
		root.dispose()
		grid.dispose()
	end)
end)
