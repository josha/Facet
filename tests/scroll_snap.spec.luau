--!strict
--[[ SCROLL SNAPPING (ADAPT-17 / audit cell B-7). Two layers, proved separately:

	  * the PURE resolver (`src/controls/scroll_snap.luau`), driven with numbers —
	    boundaries, flicks, the end of the list, an item taller than the viewport —
	    against a real `virtual_extents` index in both its forms, so the uniform and
	    variable arithmetics are held to the same answers;
	  * the WIRED control, driven through the ENGINE. Every case here scrolls with
	    `adapter.driveScroll` (the headless stand-in for a wheel, a finger and the
	    momentum after it) and reads the offset back off the control's own
	    `scrollTop` mirror, because a settle that moves a signal nothing paints is
	    not the feature.

	THE CLOCK IS SCRIPTED, always. `w.settle(n)` steps the presenter's motion clock
	by exactly 1/60 s per frame, and the snap machine times itself off that same
	clock (its quiet ramp), so a flick's speed is a number this file chooses rather
	than a wall-clock accident.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")
local Facet = require("../src") :: any
local scroll_snap = require("../src/controls/scroll_snap")
local virtual_extents = require("../src/virtual_extents")

-- ===========================================================================
-- (a) THE PURE RESOLVER
-- ===========================================================================

local UNIFORM = virtual_extents.uniform(20, 100, 0) -- content 2000
local VIEWPORT = 300 -- maxScroll 1700

local function resolve(opts: any): number?
	return scroll_snap.resolve({
		index = opts.index or UNIFORM,
		viewport = opts.viewport or VIEWPORT,
		offset = opts.offset,
		origin = if opts.origin ~= nil then opts.origin else 0,
		peak = if opts.peak ~= nil then opts.peak else 0,
	})
end

describe("ADAPT-17 (a): the snap resolver, in numbers", function()
	it("a settle between two items lands on the nearest boundary", function()
		-- past the midpoint of item 1 -> forward to item 2's edge
		expect(resolve({ offset = 77 })).toBe(100)
		-- short of it -> back to item 1's edge
		expect(resolve({ offset = 33 })).toBe(0)
	end)

	it("a settle already ON a boundary asks for no travel at all", function()
		expect(resolve({ offset = 400, origin = 400 })).toBeNil()
	end)

	it("a FLICK advances at least one item even when it died short of the midpoint", function()
		-- 40px of travel rounds back to where it came from without the flick rule
		expect(resolve({ offset = 40, origin = 0, peak = 0 })).toBe(0)
		expect(resolve({ offset = 40, origin = 0, peak = 900 })).toBe(100)
		-- ...and backwards
		expect(resolve({ offset = 460, origin = 500, peak = 900 })).toBe(400)
	end)

	it("a hard fling that already crossed several items is not pulled back to one", function()
		expect(resolve({ offset = 830, origin = 0, peak = 4000 })).toBe(800)
	end)

	it("a slow drag is not a flick: it falls back where it came from", function()
		expect(resolve({ offset = 40, origin = 0, peak = scroll_snap.FLICK_PX_S - 1 })).toBe(0)
		-- and one pixel per second faster is
		expect(resolve({ offset = 40, origin = 0, peak = scroll_snap.FLICK_PX_S })).toBe(100)
	end)

	it("the END of the list is a resting place, and settling there does not oscillate", function()
		local maxScroll = UNIFORM.content - VIEWPORT
		expect(resolve({ offset = maxScroll, origin = 1600 })).toBeNil()
		-- ...and a settle just short of it closes the gap rather than snapping back
		expect(resolve({ offset = maxScroll - 4, origin = 1600, peak = 900 })).toBe(maxScroll)
	end)

	it("content that fits the viewport has exactly one resting place and never moves", function()
		local short = virtual_extents.uniform(2, 100, 0)
		expect(resolve({ index = short, offset = 40 })).toBeNil()
	end)

	it("an item TALLER than the viewport disables snap for that settle", function()
		local tall = virtual_extents.uniform(10, 400, 0)
		expect(resolve({ index = tall, offset = 77 })).toBeNil()
		expect(resolve({ index = tall, offset = 77, peak = 4000 })).toBeNil()
	end)

	it("VARIABLE extents snap to their MEASURED boundaries, from the same index", function()
		-- leading edges 0 / 100 / 350 / 410 / 810, content 930, viewport 300
		local varied = virtual_extents.variable({ 100, 250, 60, 400, 120 }, 0)
		expect(resolve({ index = varied, viewport = 300, offset = 180 })).toBe(100)
		expect(resolve({ index = varied, viewport = 300, offset = 300 })).toBe(350)
		-- the 400px row is taller than a 300px viewport: no snap while inside it
		expect(resolve({ index = varied, viewport = 300, offset = 500 })).toBeNil()
	end)

	it("the uniform and variable indexes answer identically when the extents are equal", function()
		local extents = {}
		for _ = 1, 20 do
			table.insert(extents, 100)
		end
		local varied = virtual_extents.variable(extents, 0)
		for _, offset in { 0, 33, 77, 149, 151, 640, 1699, 1700 } do
			expect(resolve({ index = varied, offset = offset, peak = 900, origin = 0 })).toBe(
				resolve({ offset = offset, peak = 900, origin = 0 })
			)
		end
	end)

	it("keep-visible rounds OUTWARD to a boundary, and leaves an in-band item alone", function()
		-- already visible: nothing to do, snap or no snap
		expect(scroll_snap.keepVisible(UNIFORM, VIEWPORT, 0, 2, nil)).toBeNil()
		--[[ THE CASE THAT MADE THIS EXIST: a rail with a GAP, where the solver's
			minimal answer is not a resting place. Pitch 120, so the boundaries are
			0/120/240/360…; item 5 spans 480..580 and the plain answer is 280, which
			is between two of them. Rounding forward lands on 360 — item 5 still
			whole inside 360..660, and the scroller at rest. ]]
		local gapped = virtual_extents.uniform(20, 100, 20)
		local plain = gapped.offsetOf(5) + gapped.extentOf(5) - VIEWPORT
		expect(plain).toBe(280)
		local aligned = scroll_snap.keepVisible(gapped, VIEWPORT, 0, 5, plain) :: number
		expect(aligned).toBe(360)
		expect(aligned).toBeLessThanOrEqual(gapped.offsetOf(5))
		expect(aligned + VIEWPORT).toBeGreaterThanOrEqual(gapped.offsetOf(5) + gapped.extentOf(5))
		-- backward: the plain answer for a backward scroll IS the item's own edge
		expect(scroll_snap.keepVisible(gapped, VIEWPORT, 900, 3, gapped.offsetOf(3))).toBe(240)
	end)

	it("keep-visible keeps the PLAIN answer for an item taller than the viewport", function()
		local tall = virtual_extents.uniform(10, 400, 0)
		expect(scroll_snap.keepVisible(tall, 300, 0, 3, 900)).toBe(900)
	end)
end)

-- ===========================================================================
-- (b) THE WIRED CONTROL — driven through the engine
-- ===========================================================================

local ITEM = 100
local RAIL_VIEWPORT = 300
local COUNT = 20
local PATH = "/S/VL"

local function rows(n: number): { any }
	local out: { any } = {}
	for i = 1, n do
		table.insert(out, { id = `i{i}`, label = `row {i}` })
	end
	return out
end

type ListOpts = {
	snap: any?,
	itemExtent: any?,
	count: number?,
	viewportExtent: number?,
	reducedMotion: boolean?,
}

local function listWorld(opts: ListOpts?)
	local o: ListOpts = opts or {}
	local w = worldLib.new({
		viewport = { x = 0, y = 0, w = 390, h = 844 },
		reducedMotion = o.reducedMotion,
	})
	local list = Facet.Controls.VirtualList(w.core, {
		id = "VL",
		rows = w.core:signal(rows(o.count or COUNT)),
		key = function(item: any)
			return item.id
		end,
		itemExtent = if o.itemExtent ~= nil then o.itemExtent else ITEM,
		viewportExtent = o.viewportExtent or RAIL_VIEWPORT,
		overscan = 0,
		snap = o.snap,
		cell = function(item: any)
			return Facet.UI.Text({ id = "L", text = item.label, textSize = 14 })
		end,
	})
	w.present(Facet.UI.Screen({ id = "S", padding = 0, gap = 0, children = { list.blueprint } }))
	return w, list
end

-- one engine scroll, then N frames of clock: the shape every case below uses
local function driveTo(w: any, offset: number)
	w.adapter.driveScroll(PATH, { x = 0, y = offset })
end

-- a flick: `steps` engine samples one frame apart, then release
local function flick(w: any, from: number, to: number, steps: number)
	for i = 1, steps do
		driveTo(w, from + (to - from) * (i / steps))
		w.settle(1)
	end
end

describe("ADAPT-17 (b): a list with snap = 'item', driven by the engine", function()
	it("DEFAULT is 'none': a list nobody asked lands exactly where the engine left it", function()
		local w = listWorld()
		driveTo(w, 77)
		w.settle(40)
		expect(w.adapter.scrollPositionOf(PATH).y).toBe(77)
	end)

	it("settles to the nearest boundary after the gesture stops", function()
		local w, list = listWorld({ snap = "item" })
		driveTo(w, 77)
		w.settle(40)
		expect(list.scrollTop:get()).toBe(100)
	end)

	it("a FLICK that dies inside the first item still advances one card", function()
		local w, list = listWorld({ snap = "item" })
		flick(w, 0, 40, 4) -- 10px/frame = 600px/s, well past the flick floor
		w.settle(40)
		expect(list.scrollTop:get()).toBe(100)
	end)

	it("REDUCED MOTION places the offset with zero travel, on the settling frame", function()
		local w, list = listWorld({ snap = "item", reducedMotion = true })
		driveTo(w, 77)
		-- one quiet window and one frame: enough to detect the settle, far short of
		-- a spring's flight
		w.settle(10)
		expect(list.scrollTop:get()).toBe(100)
	end)

	it("...and full motion TRAVELS: the same ten frames leave it still in flight", function()
		local w, list = listWorld({ snap = "item" })
		driveTo(w, 77)
		w.settle(10)
		local mid = list.scrollTop:get()
		expect(mid).toBeGreaterThan(77)
		expect(mid).toBeLessThan(100)
		w.settle(40)
		expect(list.scrollTop:get()).toBe(100)
	end)

	it("the END of the list holds, with no overscroll oscillation", function()
		local w, list = listWorld({ snap = "item" })
		local maxScroll = COUNT * ITEM - RAIL_VIEWPORT
		driveTo(w, maxScroll)
		w.settle(60)
		expect(list.scrollTop:get()).toBe(maxScroll)
	end)

	it("keep-visible lands the focused row ON a boundary", function()
		local w, list = listWorld({ snap = "item" })
		list.focusKey("i9")
		w.settle(40)
		local top = list.scrollTop:get()
		expect(top % ITEM).toBe(0)
		-- ...and row 9 is inside the window it landed on
		expect(top).toBeLessThanOrEqual(800)
		expect(top + RAIL_VIEWPORT).toBeGreaterThanOrEqual(900)
	end)

	it("a programmatic scrollTo honours snap", function()
		local w, list = listWorld({ snap = "item" })
		list.scrollTo(w.controller, 640)
		w.settle(40)
		expect(list.scrollTop:get()).toBe(600)
	end)

	it("a row TALLER than the viewport is left where the player parked it", function()
		local w, list = listWorld({ snap = "item", itemExtent = 400 })
		driveTo(w, 77)
		w.settle(40)
		expect(list.scrollTop:get()).toBe(77)
	end)

	it("VARIABLE extents snap to the boundaries the window itself uses", function()
		local extents = { 100, 250, 60, 400, 120, 100, 100, 100 }
		local w, list = listWorld({
			snap = "item",
			viewportExtent = 300,
			count = #extents,
			itemExtent = function(_item: any, index: number)
				return extents[index] or 100
			end,
		})
		driveTo(w, 180)
		w.settle(40)
		expect(list.scrollTop:get()).toBe(100)
	end)

	it("a hand landing on a moving rail wins: the flight is abandoned where the finger is", function()
		local w, list = listWorld({ snap = "item" })
		driveTo(w, 77)
		w.settle(10) -- mid-flight
		driveTo(w, 640) -- the player grabbed it
		w.settle(3)
		expect(list.scrollTop:get()).toBeGreaterThanOrEqual(600)
		w.settle(40)
		expect(list.scrollTop:get()).toBe(600)
	end)

	--[[ THE FRAMEWORK'S OWN WRITES ARE NOT GESTURES. A variable-extent list whose
		rows resize under the player corrects the offset so the same content stays
		under the eye (the scroll anchor). Read as a TRAVEL, that correction looks
		like a flick of exactly its own size and advances a card nobody swiped —
		which is the whole reason every internal write announces a REST first. ]]
	it("an anchor correction lands where the anchor says, not one card further", function()
		local extents = { 100, 100, 100, 100, 100, 100, 100, 100 }
		local live = nil :: any
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		live = w.core:signal(1)
		local list = Facet.Controls.VirtualList(w.core, {
			id = "VL",
			rows = w.core:signal(rows(#extents)),
			key = function(item: any)
				return item.id
			end,
			itemExtent = function(_item: any, index: number, use: any)
				return extents[index] * use(live)
			end,
			viewportExtent = RAIL_VIEWPORT,
			overscan = 0,
			snap = "item",
			cell = function(item: any)
				return Facet.UI.Text({ id = "L", text = item.label, textSize = 14 })
			end,
		})
		w.present(Facet.UI.Screen({ id = "S", padding = 0, gap = 0, children = { list.blueprint } }))
		driveTo(w, 300) -- exactly on item 4's boundary
		w.settle(40)
		expect(list.scrollTop:get()).toBe(300)
		-- every row grows by half: the anchor puts item 4's leading edge back under
		-- the viewport's, which is 450 — a 150px jump the flick rule must not read
		live:set(1.5)
		w.settle(60)
		expect(list.scrollTop:get()).toBe(450)
	end)

	--[[ THE END IS A RESTING PLACE THAT NO ITEM STARTS AT. With a 250px viewport
		over a 100px pitch the last reachable boundary is 1700 and the end is 1750,
		so a settle 5px short of the end has to choose between them. Nearer wins —
		otherwise the player can never rest looking at the last card, because every
		attempt is pulled 95px back. ]]
	it("the LAST PAGE settles to the end when the end is the nearer resting place", function()
		local w, list = listWorld({ snap = "item", viewportExtent = 250 })
		local maxScroll = COUNT * ITEM - 250
		expect(maxScroll % ITEM).never().toBe(0) -- the end is NOT a boundary here
		driveTo(w, maxScroll - 5)
		w.settle(40)
		expect(list.scrollTop:get()).toBe(maxScroll)
		-- ...and a settle nearer the last boundary still goes there
		driveTo(w, 1710)
		w.settle(40)
		expect(list.scrollTop:get()).toBe(1700)
	end)

	it("a decisive drag back from the end still leaves it", function()
		local w, list = listWorld({ snap = "item", viewportExtent = 250 })
		local maxScroll = COUNT * ITEM - 250
		driveTo(w, maxScroll)
		w.settle(40)
		flick(w, maxScroll, maxScroll - 60, 4)
		w.settle(40)
		-- one whole card back from the page the end was showing, not a bounce
		expect(list.scrollTop:get()).toBe(1700)
	end)

	--[[ A WRITE THE FRAMEWORK MADE IS A REST, NOT A TRAVEL. Every internal scroll
		write announces itself before it lands, so the echo cannot be measured as a
		gesture the player never made — a keep-visible or an anchor correction read
		as a flick would advance a card nobody swiped. The travel state is what
		carries that mistake, so the travel state is what this asserts. ]]
	it("a framework write is announced as a REST: it clears the travel it did not make", function()
		local w, list = listWorld({ snap = "item" })
		flick(w, 0, 40, 4) -- a live gesture: an origin at 0 and a real peak
		expect(list._snapDebug().peak).toBeGreaterThan(scroll_snap.FLICK_PX_S)
		expect(list._snapDebug().origin).toBe(0)
		list.scrollTo(w.controller, 600)
		expect(list._snapDebug().origin).toBe(600)
		expect(list._snapDebug().peak).toBe(0)
	end)

	it("CHURN GUARD: an idle snapping list runs zero per-frame work", function()
		local w, list = listWorld({ snap = "item" })
		driveTo(w, 77)
		w.settle(60)
		expect(list.scrollTop:get()).toBe(100)
		local clock = w.pres.motionClock
		expect(clock:activeCount()).toBe(0)
		local before = clock:stats().writes
		w.settle(60)
		expect(clock:activeCount()).toBe(0)
		expect(clock:stats().writes).toBe(before)
	end)

	it("a snap value the vocabulary does not contain is refused at construction", function()
		local w = worldLib.new()
		expect(function()
			Facet.Controls.VirtualList(w.core, {
				id = "VL",
				rows = w.core:signal(rows(4)),
				key = function(item: any)
					return item.id
				end,
				itemExtent = ITEM,
				viewportExtent = RAIL_VIEWPORT,
				snap = "paging",
				cell = function()
					return Facet.UI.Text({ id = "L", text = "x", textSize = 14 })
				end,
			})
		end).toThrow()
	end)
end)

describe("ADAPT-17 (c): the same substrate on a VirtualGrid's scroll axis", function()
	local GRID = "/S/VG"

	local function gridWorld(snap: any?)
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		local grid = Facet.Controls.VirtualGrid(w.core, {
			id = "VG",
			items = w.core:signal(rows(40)),
			key = function(item: any)
				return item.id
			end,
			columns = 2,
			itemExtent = ITEM,
			viewportExtent = RAIL_VIEWPORT,
			overscan = 0,
			snap = snap,
			width = { type = "fixed", px = 320 },
			cell = function(item: any)
				return Facet.UI.Text({ id = "L", text = item.label, textSize = 14 })
			end,
		})
		w.present(Facet.UI.Screen({ id = "S", padding = 0, gap = 0, children = { grid.blueprint } }))
		return w, grid
	end

	it("a grid settles to a LINE boundary", function()
		local w, grid = gridWorld("item")
		w.adapter.driveScroll(GRID, { x = 0, y = 77 })
		w.settle(40)
		expect(grid.scrollTop:get()).toBe(100)
	end)

	it("...and a grid nobody asked keeps the engine's own offset", function()
		local w, grid = gridWorld()
		w.adapter.driveScroll(GRID, { x = 0, y = 77 })
		w.settle(40)
		expect(grid.scrollTop:get()).toBe(77)
	end)
end)
