--!strict
--[[
	THE LAZY GRID, SIDEWAYS — `newVirtualGrid { axis = "x" }`.

	THE REFUSAL THIS REPLACES, verbatim from the shipped control: *"there is no
	sideways grid here yet. A grid's line holds `columns` cells, and `UI.Grid` wraps
	row-major ONLY: there is no column-major mode to give a horizontal grid its
	lanes, and hand-rolling one would be a second column arithmetic beside the flow
	grid's."* That was never a refusal of principle — it was a missing capability,
	named. `UI.Grid { flow = "column" }` is now that capability
	(`tests/grid_column_flow.spec.luau`), so the horizontal band can BE a real
	`UI.Grid` exactly as the vertical one is, with the lane formula EXECUTING rather
	than copied into the control.

	WHAT THIS SPEC PINS, and it is the vertical grid's own bar rather than a lighter
	one:

	  · THE BAND IS A REAL COLUMN-MAJOR `UI.Grid`. Proved by a DIFFERENTIAL against
	    a plain `UI.Grid { flow = "column" }` of the same cross extent, short last
	    line included — so the control cannot drift into a second lane arithmetic
	    that merely agrees today.

	  · LAZINESS IS REAL AND TWO-SIDED. An EXACT build count, so "mount nothing"
	    fails exactly as "mount everything" does, plus the stronger claim: the count
	    is INDEPENDENT OF N. Both numbers are the vertical grid's own, because the
	    windowing arithmetic is unchanged — `virtual_extents` is a prefix sum over
	    numbers and the word "item" appears nowhere in its interface.

	  · **THE FOCUS RING TRANSPOSES, AND IT IS NOT THE TRANSPOSE OF A LIST'S.** A
	    grid's ring is two-dimensional and the focus graph's is not, so one axis is
	    a declared group and the other arrives through `navigateIntercept`. Which is
	    which flips with the scroll axis, and the rule is one sentence: THE GROUP'S
	    AXIS IS THE LANE AXIS, which is always PERPENDICULAR to the scroll. Document
	    order walks a line's lanes before it moves to the next line, so on
	    `axis = "y"` (row-major lanes across) ±1 is sideways and the group is
	    `horizontal`; on `axis = "x"` (column-major lanes down) ±1 is DOWNWARD and
	    the group is `vertical`. `newVirtualList` transposes the other way, because
	    its line holds one item and its document order IS its scroll axis. Declaring
	    the list's answer here would be reachable and wrong in SHAPE — Right walking
	    one cell down instead of a whole line — which is the bug class that passes
	    every reachability test and feels broken.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local virtual_grid = require("../src/controls/virtual_grid")
local fake_target = require("../tests/lib/fake_target")

local CROSS = 320 -- the strip's height: the axis the lanes divide
local LANES = 4
local LINE = 40 -- one LINE of cells' width — the scroll-axis extent
local VIEWPORT = 200 -- the scroll host's width

local function makeItems(n: number): { { id: string, label: string } }
	local items = table.create(n)
	for i = 1, n do
		items[i] = { id = `i{i}`, label = `Item {i}` }
	end
	return items
end

--[[ A PRESENTED HORIZONTAL GRID. Its CROSS axis is the height and it FILLS —
	`width` is refused on `axis = "x"` because there the width IS the scroll axis —
	so the strip is wrapped in a box of the height under test, which is the same
	instruction `newVirtualList` gives for its own horizontal mode. ]]
local function world(opts: any?)
	local options: any = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local items = core:signal(options.items or makeItems(options.count or 400))
	local built = 0
	local activations: { any } = {}
	local grid = virtual_grid.build(Facet, core, {
		id = "HG",
		axis = "x",
		items = items,
		key = function(item: any)
			return item.id
		end,
		columns = options.columns or LANES,
		itemExtent = options.itemExtent or LINE,
		gap = options.gap,
		rowGap = options.rowGap,
		viewportExtent = options.viewportExtent or VIEWPORT,
		overscan = options.overscan,
		cell = function(item: any)
			built += 1
			return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
		onActivate = function(item: any, meta: any)
			table.insert(activations, { item = item, meta = meta })
		end,
	})
	local screen = Facet.UI.Screen({
		id = "S",
		padding = 0,
		gap = 0,
		children = {
			Facet.UI.VStack({
				id = "Wrap",
				padding = 0,
				gap = 0,
				width = { type = "fill" },
				height = { type = "fixed", px = options.cross or CROSS },
				children = { grid.blueprint },
			}),
		},
	})
	local handle = pres.present(screen)
	pres.refresh()
	grid.bindNativeScroll(handle.controller)
	local w: any = {
		core = core,
		grid = grid,
		items = items,
		adapter = adapter,
		system = system,
		pres = pres,
		handle = handle,
		activations = activations,
	}
	function w.builtSoFar(): number
		return built
	end
	function w.cellRect(key: string): any
		return handle.controller.rectOf(`/S/Wrap/HG/Canvas/Band/W/[{key}]/Cell`)
	end
	function w.rect(path: string): any
		return handle.controller.rectOf(path)
	end
	function w.canvas(): any
		return handle.controller.rectOf("/S/Wrap/HG/Canvas")
	end
	return w
end

local function cellHit(key: string): string
	return `/S/Wrap/HG/Canvas/Band/W/[{key}]/Cell/Hit`
end

--[[ ── A. THE AXIS IS ACCEPTED, AND THE CROSS-AXIS DIM MOVES WITH IT ────────── ]]

describe("VirtualHGrid: the axis the control used to refuse", function()
	it('axis = "x" builds, and the dump says which way it runs', function()
		local w = world({ count = 20 })
		local d = w.grid.dump()
		expect(`{d.axis} lanes={d.lanes} lines={d.lineCount}`).toBe("x lanes=4 lines=5")
		w.grid.dispose()
	end)

	it("...and an axis that is neither is still refused, naming the legal pair", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			return virtual_grid.build(Facet, core, {
				id = "HG",
				axis = "diagonal",
				items = core:signal(makeItems(4)),
				key = function(i: any)
					return i.id
				end,
				columns = 2,
				itemExtent = 40,
				viewportExtent = 200,
				cell = function()
					return Facet.UI.Text({ id = "L", text = "x" })
				end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "diagonal", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "axis", 1, true) ~= nil).toBe(true)
	end)

	--[[ `width` IS THE CROSS AXIS, AND ONLY A VERTICAL GRID HAS ONE THERE. On
		`axis = "x"` the width IS the scroll axis — that is what `viewportExtent`
		declares — so accepting both would be two answers to one dim. Same refusal,
		same reason, as `newVirtualList`'s. ]]
	it("`width` is refused on the horizontal axis, and the message names the route", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			return virtual_grid.build(Facet, core, {
				id = "HG",
				axis = "x",
				items = core:signal(makeItems(4)),
				key = function(i: any)
					return i.id
				end,
				columns = 2,
				itemExtent = 40,
				viewportExtent = 200,
				width = { type = "fixed", px = 300 },
				cell = function()
					return Facet.UI.Text({ id = "L", text = "x" })
				end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "viewportExtent", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "height", 1, true) ~= nil).toBe(true)
	end)
end)

--[[ ── B. LAZINESS, TWO-SIDED, AND INDEPENDENT OF N ─────────────────────────── ]]

describe("VirtualHGrid: only the windowed cells are ever built", function()
	it("10 000 items, 4 lanes: the EXACT cells of the windowed lines are built and no others", function()
		--[[ TWO-SIDED ON PURPOSE. An exact count fails "mount nothing" exactly as
			hard as "mount everything"; a `>= 1` or a `< N` would pass one of the two
			ways this control can be broken. 200px of viewport over a 40px line pitch
			is five whole lines, plus two lines of overscan behind the trailing edge
			and none in front of the leading one: seven lines x four lanes = 28. It is
			the vertical grid's own number, because the windowing arithmetic is the
			same prefix sum over the same unit. ]]
		local w = world({ count = 10000 })
		expect(w.builtSoFar()).toBe(28)
		local d = w.grid.dump()
		expect(`lines={d.lines[1]}..{d.lines[2]} window={#d.window}`).toBe("lines=1..7 window=28")
		expect(d.content).toBe(2500 * LINE)

		-- ...and scrolling deep builds only the cells that arrived
		local atTop = w.builtSoFar()
		w.adapter.driveScroll("/S/Wrap/HG", { x = 100000, y = 0 })
		w.pres.refresh()
		expect(w.builtSoFar() - atTop).toBe(28)
		local deep = w.grid.dump()
		expect(`lines={deep.lines[1]}..{deep.lines[2]}`).toBe("lines=2494..2500")
		expect(deep.scrollTop > 0).toBe(true)
	end)

	it("...and the build count is INDEPENDENT OF N — the property 'only as needed' names", function()
		--[[ THE STRONGER CLAIM. An exact count could be met by a control that builds
			a fixed prefix; only the differential across two collection sizes says the
			work does not grow with the data. 250x the items, the same cells. ]]
		local function buildsFor(n: number): number
			local w = world({ count = n })
			local built = w.builtSoFar()
			w.grid.dispose()
			return built
		end
		expect(`{buildsFor(40)}/{buildsFor(10000)}`).toBe("28/28")
	end)
end)

--[[ ── C. THE BAND IS A REAL COLUMN-MAJOR `UI.Grid` ─────────────────────────── ]]

describe("VirtualHGrid: the mounted band's lanes are the flow grid's own arithmetic", function()
	it("the lane heights match a plain UI.Grid { flow = 'column' } of the same cross extent", function()
		--[[ THE DIFFERENTIAL THAT KEEPS ONE ARITHMETIC ONE. The control could have
			grown its own `floor((innerH - gap * (lanes - 1)) / lanes)`; comparing
			against the eager grid is what makes the two unable to drift apart. ]]
		local w = world({ count = 20, gap = 6 })
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local pres = Facet.newPresenter(core, env, fake_target.new(), Facet.newActionSystem(core))
		local kids = {}
		for i = 1, 20 do
			table.insert(
				kids,
				Facet.UI.Box({
					id = `e{i}`,
					width = { type = "fixed", px = LINE },
					height = { type = "fill" },
				})
			)
		end
		local eager = pres.present(Facet.UI.Screen({
			id = "E",
			padding = 0,
			gap = 0,
			children = {
				Facet.UI.Grid({
					id = "G",
					flow = "column",
					columns = LANES,
					gap = 6,
					rowGap = 0,
					width = { type = "fill" },
					height = { type = "fixed", px = CROSS },
					children = kids,
				}),
			},
		}))
		pres.refresh()
		local eagerCell = eager.controller.rectOf("/E/G/e1")
		local eagerGrid = eager.controller.rectOf("/E/G")
		local lazyCell = w.cellRect("i1")
		local lazyBand = w.rect("/S/Wrap/HG/Canvas/Band")
		expect(`h={lazyCell.h}`).toBe(`h={eagerCell.h}`)
		-- lane 2 sits one lane + one gap down, in both
		expect(`{w.cellRect("i2").y - lazyBand.y}`).toBe(`{eager.controller.rectOf("/E/G/e2").y - eagerGrid.y}`)
		-- ...and the SHORT LAST LINE keeps its lane height rather than stretching:
		-- the flow grid derives the lane from the OFFER and the lane count, never
		-- from how many cells turned up
		local short = world({ count = 18, gap = 6 })
		expect(short.cellRect("i17").h).toBe(lazyCell.h)
		short.grid.dispose()
		w.grid.dispose()
	end)

	it("each mounted cell is exactly its own LINE's extent wide, and lines stack rightward", function()
		local w = world({ count = 100 })
		local canvas = w.canvas()
		for _, probe in
			{
				{ key = "i1", line = 1, lane = 1 },
				{ key = "i7", line = 2, lane = 3 },
				{ key = "i28", line = 7, lane = 4 },
			}
		do
			local r = w.cellRect(probe.key)
			expect(`{probe.key} x={r.x - canvas.x} w={r.w}`).toBe(`{probe.key} x={(probe.line - 1) * LINE} w={LINE}`)
			-- the lane pitch is the cross extent divided by the lane count
			expect(`{probe.key} y={r.y - canvas.y}`).toBe(`{probe.key} y={(probe.lane - 1) * (CROSS // LANES)}`)
		end
		w.grid.dispose()
	end)

	it("the canvas is the FULL virtual extent along x, so the engine's scroll range is the collection", function()
		local w = world({ count = 1000 })
		local canvas = w.canvas()
		expect(canvas.w).toBe(250 * LINE)
		-- ...and the viewport is what the author declared, not the canvas
		expect(w.rect("/S/Wrap/HG").w).toBe(VIEWPORT)
		expect(w.rect("/S/Wrap/HG").h).toBe(CROSS)
		expect(#w.handle.controller.diagnostics()).toBe(0)
		w.grid.dispose()
	end)
end)

--[[ ── D. THE FOUR INPUTS, WITH THE RING A QUARTER TURN ROUND ────────────────── ]]

describe("VirtualHGrid pointer and touch (no consumer wiring)", function()
	it("a native scroll moves along X and slides the window; it never activates a cell", function()
		local w = world()
		expect(w.grid.scrollTop:get()).toBe(0)
		w.adapter.driveScroll("/S/Wrap/HG", { x = 400, y = 0 })
		expect(w.grid.scrollTop:get()).toBe(400)
		w.pres.refresh()
		expect(w.grid.debugWindow().i1).toBe(nil)
		expect(w.grid.debugWindow().i41).toBe(true)
		-- the cell sits at its ABSOLUTE canvas offset: the engine translates the
		-- canvas by CanvasPosition and the framework never does
		expect(w.adapter.node(cellHit("i41")).rect.x - w.canvas().x).toBe(10 * LINE)
		expect(#w.activations).toBe(0)
	end)

	it("a garbage mirror value cannot mount a window before the leading edge", function()
		local w = world()
		w.adapter.driveScroll("/S/Wrap/HG", { x = -300, y = 0 })
		expect(w.grid.debugWindow().i1).toBe(true)
		expect(w.grid.dump().scrollTop).toBe(0)
	end)

	it("a cell tap activates through the auto-composed handleActivate", function()
		local w = world()
		w.adapter.tap(cellHit("i7"), { pointer = "touch" })
		expect(#w.activations).toBe(1)
		expect(w.activations[1].item.id).toBe("i7")
	end)
end)

describe("VirtualHGrid keyboard and gamepad: the ring is the TRANSPOSE, not a copy", function()
	it("Down/Up steps ONE CELL — the group's axis is the LANE axis, which is vertical here", function()
		--[[ THE DECISION THIS CASE EXISTS FOR. The mounted band is column-major, so
			its document order walks a line's lanes DOWNWARD before it moves to the
			next line — which makes ±1 in the contributed group a vertical step and
			the group's declared axis `vertical`. On `axis = "y"` the identical rule
			produces `horizontal`. Getting this backwards is reachable and wrong in
			SHAPE: every cell would still be focusable, and Down would walk visually
			rightward across the strip. ]]
		local w = world()
		expect(w.pres.focus.focused:get()).toBe(cellHit("i1")) -- auto-focus first cell
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i2"))
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i3"))
		w.system.deviceKey("Up", true)
		w.system.deviceKey("Up", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i2"))
	end)

	it("Right/Left moves a whole LINE, not one cell", function()
		local w = world()
		expect(w.pres.focus.focused:get()).toBe(cellHit("i1"))
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i5")) -- NOT i2
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i9"))
		w.system.deviceKey("Left", true)
		w.system.deviceKey("Left", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i5"))
	end)

	it("focus past the window edge scrolls the line into view", function()
		local w = world() -- five visible lines + overscan 2
		for _ = 1, 9 do
			w.system.deviceKey("Right", true)
			w.system.deviceKey("Right", false)
			w.pres.refresh()
		end
		local focused = w.pres.focus.focused:get() :: string
		local key = string.match(focused, "%[(.-)%]/Cell/Hit$") :: string
		local index = tonumber(string.match(key, "i(%d+)")) :: number
		expect(index).toBe(1 + 9 * LANES) -- nine whole lines along
		local left = w.grid.scrollTop:get()
		expect(left > 0).toBe(true)
		local lineLeft = 9 * LINE
		expect(lineLeft >= left).toBe(true)
		expect(lineLeft + LINE <= left + VIEWPORT).toBe(true)
	end)

	it("Down off the END of a line crosses into the next one, and it is scrolled in", function()
		-- the group's own axis carries this one: stepping Down off the last lane is
		-- how the ring reaches line 2, and nothing in the intercept sees it
		local w = world()
		for _ = 1, 27 do
			w.system.deviceKey("Down", true)
			w.system.deviceKey("Down", false)
			w.pres.refresh()
		end
		expect(w.pres.focus.focused:get()).toBe(cellHit("i28")) -- line 7, past the first five
		local left = w.grid.scrollTop:get()
		expect(left > 0).toBe(true)
		local lineLeft = 6 * LINE
		expect(lineLeft >= left).toBe(true)
		expect(lineLeft + LINE <= left + VIEWPORT).toBe(true)
	end)

	it("Return and ButtonA activate the focused cell", function()
		local w = world()
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		expect(w.pres.focus.focused:get()).toBe(cellHit("i5"))
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(#w.activations).toBe(1)
		expect(w.activations[1].item.id).toBe("i5")
		expect(w.activations[1].meta.source).toBe("action")

		local g = world()
		g.system.deviceKey("DPadDown", true)
		g.system.deviceKey("DPadDown", false)
		expect(g.pres.focus.focused:get()).toBe(cellHit("i2"))
		g.system.deviceKey("DPadRight", true)
		g.system.deviceKey("DPadRight", false)
		expect(g.pres.focus.focused:get()).toBe(cellHit("i6"))
		g.system.deviceKey("ButtonA", true)
		g.system.deviceKey("ButtonA", false)
		expect(#g.activations).toBe(1)
		expect(g.activations[1].item.id).toBe("i6")
	end)
end)

return true
