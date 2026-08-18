--!strict
--[[
	`newVirtualList.rowGap` — THE VERTICAL GUTTER BETWEEN ROW SLOTS.

	`newTable` has always exposed `rowGap` (src/controls/table.luau); VirtualList
	did not, so its pitch was hard-wired to `rowHeight` and a consumer that wanted
	breathing room between plates had exactly one workaround: hand in the PITCH as
	the row height and inset the cell. That workaround is wrong in the one place it
	matters — it inflates the row's HIT node into the gutter, so a press in the
	dead space between two plates activates one of them.

	This spec pins the contract the field ships with:

	  · the WINDOWING arithmetic (canvas extent, clamp, window membership, the
	    keep-visible target) is index x PITCH, pitch = rowHeight + rowGap;
	  · the CONTENT EXTENT carries no TRAILING gutter — N rows span
	    N*rowHeight + (N-1)*rowGap, exactly like a UIListLayout's padding;
	  · the row's own box stays `rowHeight` tall, so the gutter is DEAD SPACE: a
	    pointer in it hits neither neighbour;
	  · the drop hit-test reads the same pitch, so an insertion slot lands where
	    the gutter is rather than one row short;
	  · `rowGap = 0` (the default) reproduces the pre-field arithmetic byte for
	    byte — every existing list is untouched.
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

-- a controller-shaped scroll stub (the same seam virtualization.spec uses): the
-- headless stand-in for the engine moving CanvasPosition.
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
		rowHeight = opts.rowHeight or 56,
		rowGap = opts.rowGap,
		viewportHeight = opts.viewportHeight or 498,
		overscan = opts.overscan or 2,
		cell = function(item: any)
			return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
	})
end

-- a PRESENTED list, so the real solver gives us rects to measure the row box and
-- the gutter against (a dump can only report the numbers it was handed)
local function world(opts: any?)
	local options = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system)
	local rows = core:signal(makeRows(options.count or 8))
	local reorders: { any } = {}
	local list = virtual_list.build(Facet, core, {
		id = "VL",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = options.rowHeight or 56,
		rowGap = options.rowGap,
		viewportHeight = options.viewportHeight or 498,
		overscan = options.overscan or 2,
		reorderable = options.reorderable,
		onReorder = if options.reorderable
			then function(key: string, toIndex: number)
				table.insert(reorders, { key = key, toIndex = toIndex })
			end
			else nil,
		cell = function(item: any)
			return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
	})
	local screen = Facet.UI.Screen({ id = "S", children = { list.blueprint } })
	local handle = pres.present(screen)
	pres.refresh()
	list.bindNativeScroll(handle.controller)
	local w: any = {
		core = core,
		list = list,
		rows = rows,
		adapter = adapter,
		handle = handle,
		reorders = reorders,
	}
	function w.hitPath(key: string): string
		return `/S/VL/Canvas/W/[{key}]/Row/Hit`
	end
	function w.rect(key: string): any
		return handle.controller.rectOf(w.hitPath(key))
	end
	function w.rowY(key: string): number
		local r = w.rect(key)
		assert(r ~= nil, `row {key} is not mounted`)
		return r.y + r.h / 2
	end
	function w.lift(key: string)
		local y = w.rowY(key)
		adapter.driveDragStart(w.hitPath(key), { x = 100, y = y, pointerType = "mouse" })
		adapter.driveDragContinue(w.hitPath(key), { x = 100, y = y + 10, pointerType = "mouse" }, { x = 0, y = 0 })
	end
	function w.moveTo(key: string, y: number)
		adapter.driveDragContinue(w.hitPath(key), { x = 100, y = y, pointerType = "mouse" }, { x = 0, y = 0 })
	end
	return w
end

describe("VirtualList.rowGap: the gutter is in the PITCH, never in the row", function()
	it("is refused unless it is a non-negative number or a Readable<number>", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(4))
		expect(pcall(function()
			newList(core, { rows = rows, rowGap = -1 })
		end)).toBe(false)
		expect(pcall(function()
			newList(core, { rows = rows, rowGap = "6" })
		end)).toBe(false)
		-- zero is legal and is the DEFAULT (a gutter of nothing is a real answer)
		local zero = newList(core, { rows = rows, rowGap = 0 })
		expect(zero.dump().rowGap).toBe(0)
		expect(newList(core, { rows = rows }).dump().rowGap).toBe(0)
		zero.dispose()
	end)

	it("carries the resolved gutter in the dump", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(8))
		local list = newList(core, { rows = rows, rowGap = 6 })
		local d = list.dump()
		expect(`{d.rowHeight}|{d.rowGap}`).toBe("56|6")
		-- and a LIVE gutter re-derives with its Readable, exactly like rowHeight
		local gap = core:signal(6)
		local live = newList(core, { rows = rows, rowGap = gap })
		expect(live.dump().rowGap).toBe(6)
		gap:set(10)
		expect(live.dump().rowGap).toBe(10)
		list.dispose()
		live.dispose()
	end)

	it("the CONTENT EXTENT is N*rowHeight + (N-1)*rowGap — no trailing gutter", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(8))
		-- legacy's own racer list: 8 rows of 56 on a 62 pitch
		local list = newList(core, { rows = rows, rowGap = 6, viewportHeight = 200 })
		list.bindNativeScroll(scrollStub(), "/VL")
		-- the scroll clamp is the whole truth about the content extent: the last
		-- reachable top is extent - viewport
		list.scrollTop:set(100000)
		expect(list.dump().scrollTop).toBe(8 * 56 + 7 * 6 - 200)
		-- ...and one row alone has no gutter at all
		rows:set(makeRows(1))
		list.scrollTop:set(100000)
		expect(list.dump().scrollTop).toBe(0)
		list.dispose()
	end)

	it("window membership steps on the PITCH, not the row height", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(200))
		-- 62 pitch, a 124 px viewport = exactly 2 whole slots, no overscan
		local list = newList(core, { rows = rows, rowGap = 6, viewportHeight = 124, overscan = 0 })
		expect(list.dump().window).toEqual({ "r1", "r2" })
		--[[ THE DISCRIMINATOR. Park the canvas on the top of slot 11 (10 x 62 =
			620). Pitch arithmetic answers `floor(620/62) + 1 = 11` and `ceil(124/62)
			= 2` visible; the pre-field height-only arithmetic answers
			`floor(620/56) + 1 = 12` over `ceil(124/56) = 3` rows — a whole row of
			drift and a third mounted row, which is exactly the mis-windowing the
			pitch workaround hides. ]]
		list.scrollTop:set(620)
		expect(list.dump().window).toEqual({ "r11", "r12" })
		list.dispose()
	end)

	it("keep-visible brings the ROW into the band, measured on the pitch", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(100))
		local list = newList(core, { rows = rows, rowGap = 6, viewportHeight = 200 })
		local ctrl = scrollStub()
		list.bindNativeScroll(ctrl, "/VL")
		list.focusKey("r20")
		-- row 20's slot starts at 19*62 = 1178 and the row itself is 56 tall, so
		-- the minimal downward scroll parks its BOTTOM on the band's bottom edge
		expect(ctrl.lastPos().y).toBe(19 * 62 + 56 - 200)
		-- scrolling back up parks its TOP on the band's top edge
		list.focusKey("r1")
		expect(ctrl.lastPos().y).toBe(0)
		list.dispose()
	end)

	it("the row's own box stays rowHeight tall — the gutter is DEAD SPACE", function()
		local w = world({ rowGap = 6, count = 8 })
		local a = w.rect("r1")
		local b = w.rect("r2")
		expect(a ~= nil and b ~= nil).toBe(true)
		-- the HIT is the row height, never the pitch…
		expect(a.h).toBe(56)
		expect(b.h).toBe(56)
		-- …and the two are 62 apart, so 6 px of the band belong to neither
		expect(b.y - a.y).toBe(62)
		expect(b.y - (a.y + a.h)).toBe(6)
	end)

	it("rowGap = 0 reproduces the pre-field arithmetic exactly", function()
		local w = world({ count = 8 })
		local a = w.rect("r1")
		local b = w.rect("r2")
		expect(b.y - a.y).toBe(56)
		expect(b.y - (a.y + a.h)).toBe(0)
		local core = Facet.newCore()
		local rows = core:signal(makeRows(8))
		local list = newList(core, { rows = rows, viewportHeight = 200 })
		list.bindNativeScroll(scrollStub(), "/VL")
		list.scrollTop:set(100000)
		expect(list.dump().scrollTop).toBe(8 * 56 - 200)
		list.dispose()
	end)

	it("the drop hit-test reads the same pitch: a pointer in the gutter is a slot boundary", function()
		local w = world({ rowGap = 6, count = 8, reorderable = true })
		w.lift("r1")
		local r4 = w.rect("r4")
		-- the gutter BELOW row 4 is the boundary between slot 4 and slot 5; with
		-- the dragged r1 removed first, landing there is index 4
		w.moveTo("r1", r4.y + r4.h + 3)
		expect(w.list.dropIndex:get()).toBe(4)
		-- the middle of row 6 is past its own midpoint boundary
		w.moveTo("r1", w.rowY("r6") + 20)
		expect(w.list.dropIndex:get()).toBe(6)
	end)

	it("a bounded window is still bounded with a gutter (the canvas never mounts the list)", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(1000))
		local list = newList(core, { rows = rows, rowGap = 6, viewportHeight = 620 })
		local root = mountLib.mount(core, list.blueprint)
		local mounted = 0
		for _ in list.debugWindow() do
			mounted += 1
		end
		-- ceil(620/62) = 10 visible + 2 overscan below (the top is clamped)
		expect(mounted).toBe(12)
		list.scrollTop:set(62 * 500)
		mounted = 0
		for _ in list.debugWindow() do
			mounted += 1
		end
		expect(mounted).toBe(14) -- + 2 overscan above
		root.dispose()
		list.dispose()
	end)
end)
