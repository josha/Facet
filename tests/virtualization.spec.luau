--!strict
-- Phase 4 fixed-height keyed-row virtualization hardening (design §10.5 first
-- release; UI-RUNTIME-002, UI-LIFE-002, UI-FOCUS-001): VirtualList windows a
-- large keyed collection over a fixed row height with bounded overscan.
-- Hardened invariants: bounded mounted-row count at any scroll position;
-- surviving rows never remount across window slides (keyed identity); a
-- same-window scroll delta is rect-writes-only (zero structural dirties);
-- logical focus works by ITEM KEY (materialize + scroll into view, nearest
-- surviving neighbor on removal); a re-entered row's dump equals a fresh
-- row's dump (no state bleed — item state lives in the item scope and dies
-- with it); async cell resources cancel on window exit with stale
-- completions rejected; scroll storms are registry-neutral.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local resources = require("../src/async/resources")
local mountLib = require("../src/mount")

local function makeRows(n: number): { { id: string, label: string } }
	local rows = {}
	for i = 1, n do
		table.insert(rows, { id = `r{i}`, label = `Row {i}` })
	end
	return rows
end

local function countMountedRows(list: any): number
	local n = 0
	for _ in list.debugWindow() do
		n += 1
	end
	return n
end

-- a controller-shaped scroll stub: the headless stand-in for the renderer's
-- native-scroll seam (native-substrate NS-A2). scrollTo echoes the position back
-- to every observer synchronously, exactly like the engine moving CanvasPosition
-- and firing observeScroll — so a bound VirtualList's keep-visible materializes.
local function scrollStub()
	local pos = { x = 0, y = 0 }
	local observers: { any } = {}
	local ctrl = {}
	function ctrl.observeScroll(_path: string, fn: any): () -> ()
		table.insert(observers, fn)
		return function()
			for i, f in observers do
				if f == fn then
					table.remove(observers, i)
					break
				end
			end
		end
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

local function newList(core: any, opts: { rows: any, viewportHeight: number?, overscan: number? })
	return virtual_list.build(Facet, core, {
		id = "VL",
		rows = opts.rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = 40,
		viewportHeight = opts.viewportHeight or 400, -- 10 visible rows
		overscan = opts.overscan or 2,
		cell = function(item: any)
			return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
	})
end

describe("virtualization: fixed-height keyed rows (§10.5)", function()
	it("mounts a bounded window (visible + overscan), never the whole list", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(1000))
		local list = newList(core, { rows = rows })
		local root = mountLib.mount(core, list.blueprint)
		-- 10 visible + 2 overscan below (top clamped at 0)
		expect(countMountedRows(list)).toBeLessThanOrEqual(14)
		expect(countMountedRows(list)).toBeGreaterThanOrEqual(10)
		-- deep jump: window follows, still bounded
		list.scrollTop:set(20000) -- row 500 area
		expect(countMountedRows(list)).toBeLessThanOrEqual(15)
		local mounted = root.counters().mounted
		expect(mounted < 100).toBeTruthy() -- 1000 rows must NOT be mounted
		root.dispose()
	end)

	it("a same-window scroll delta is ZERO framework writes (the engine owns the offset)", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(100))
		local list = newList(core, { rows = rows })
		local root = mountLib.mount(core, list.blueprint)
		root.takeDirty()
		list.scrollTop:set(10) -- a same-window mirror change (overscan 2 x 40px)
		local sawStructure = false
		local sawArrange = false
		for _, entry in root.takeDirty() do
			if entry.class == "structure" then
				sawStructure = true
			elseif entry.class == "arrange" then
				sawArrange = true
			end
		end
		-- native canvas (native §6): rows sit at ABSOLUTE offsets and the ENGINE
		-- owns the live offset, so a same-window mirror delta produces NO structure
		-- AND NO arrange (was arrange-only under the old offsetY-vs-scrollTop trick)
		expect(sawStructure).toBeFalsy()
		expect(sawArrange).toBeFalsy()
		root.dispose()
	end)

	it("surviving rows keep their mounted identity across a window slide", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(100))
		local list = newList(core, { rows = rows })
		local root = mountLib.mount(core, list.blueprint)
		local runsBefore = root.counters().factoryRuns
		local survivorPath = list.pathOf("r12") -- inside both windows
		expect(survivorPath == nil).toBeFalsy()
		list.scrollTop:set(80) -- slide by 2 rows: r12 survives
		expect(list.pathOf("r12")).toBe(survivorPath)
		-- factory runs grew ONLY for newly-entered rows (2 rows * nodes/row),
		-- never for survivors; a full remount would re-run every windowed row
		local runsAfter = root.counters().factoryRuns
		expect(runsAfter - runsBefore <= 3 * 4).toBeTruthy()
		root.dispose()
	end)

	it("focuses an off-window item BY KEY: materializes and scrolls it into view", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(500))
		local list = newList(core, { rows = rows })
		local root = mountLib.mount(core, list.blueprint)
		-- keep-visible issues a programmatic scrollTo through the bound controller;
		-- the stub echoes it back to the scrollTop mirror (as the engine would),
		-- which materializes the row. Standalone mount => pass the path explicitly.
		local ctrl = scrollStub()
		list.bindNativeScroll(ctrl, "/VL")
		expect(list.pathOf("r400")).toBeNil() -- far outside the window
		local path = list.focusKey("r400")
		expect(path == nil).toBeFalsy()
		expect(list.pathOf("r400")).toBe(path)
		-- the row is inside the visible band after the scroll
		local top = list.scrollTop:get()
		local rowTop = 399 * 40
		expect(rowTop >= top).toBeTruthy()
		expect(rowTop + 40 <= top + 400).toBeTruthy()
		-- the keep-visible target was the exact scrollTo the control wrote
		expect(ctrl.lastPos().y).toBe(top)
		root.dispose()
	end)

	it("keeps focus on the nearest surviving neighbor when the focused row is removed", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(30))
		local list = newList(core, { rows = rows })
		local root = mountLib.mount(core, list.blueprint)
		list.focusKey("r5")
		expect(list.focusedKey:get()).toBe("r5")
		local next = makeRows(30)
		table.remove(next, 5) -- r5 gone
		rows:set(next)
		expect(list.focusedKey:get()).toBe("r6") -- following neighbor survives
		root.dispose()
	end)

	it("a re-entered row's dump equals a fresh row's dump (no state bleed)", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(100))
		local list = newList(core, { rows = rows })
		local root = mountLib.mount(core, list.blueprint)
		local function dumpOf(tree: any, path: string): any
			local found: any = nil
			local function walk(node: any)
				if node.path == path then
					found = node
				end
				for _, child in node.children or {} do
					walk(child)
				end
			end
			walk(tree.tree)
			return found
		end
		local path = list.pathOf("r1") :: string
		local fresh = dumpOf(root.dump(), path)
		expect(fresh == nil).toBeFalsy()
		list.scrollTop:set(2000) -- r1 leaves the window (unmounts)
		expect(list.pathOf("r1")).toBeNil()
		list.scrollTop:set(0) -- r1 re-enters, mounted fresh
		local reentered = dumpOf(root.dump(), path)
		expect(reentered == nil).toBeFalsy()
		expect(reentered.factoryRuns).toBe(fresh.factoryRuns)
		expect(reentered.class).toBe(fresh.class)
		root.dispose()
	end)

	it("cancels async cell resources on window exit; late completion is stale", function()
		local core = Facet.newCore()
		local provider = resources.newProvider(core, { maxConcurrent = 4 })
		local acquired: { [string]: any } = {}
		local rows = core:signal(makeRows(100))
		local list = virtual_list.build(Facet, core, {
			id = "VL",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			rowHeight = 40,
			viewportHeight = 400,
			overscan = 0,
			cell = function(item: any, ctx: any)
				-- item-scope-owned async acquire (the §10.3 contract)
				acquired[item.id] = provider.acquire(ctx.scope, `img/{item.id}`)
				return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
		})
		local root = mountLib.mount(core, list.blueprint)
		local first = provider.pendingRequests()[1]
		expect(first == nil).toBeFalsy()
		list.scrollTop:set(4000) -- the requesting rows all leave the window
		-- their requests were cancelled: the late completion must be stale
		expect(provider.complete(first.key, first.generation, "late")).toBe("stale")
		root.dispose()
		expect(provider.counters().handles).toBe(0)
	end)

	it("scroll storms leave every registry at baseline after dispose", function()
		local core = Facet.newCore()
		local baseline = core:counters()
		local rows = core:signal(makeRows(300))
		local list = newList(core, { rows = rows })
		local root = mountLib.mount(core, list.blueprint)
		for i = 1, 60 do
			list.scrollTop:set((i * 137) % (300 * 40 - 400))
		end
		root.dispose()
		list.dispose()
		rows:dispose()
		local after = core:counters()
		for key, value in baseline :: { [string]: number } do
			expect(after[key]).toBe(value)
		end
	end)
end)
