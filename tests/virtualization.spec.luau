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

--[[ THE LAZINESS INSTRUMENT (wave T15; M2-review finding A-H1).

	`src/init.luau` requires fifteen of the nineteen composite controls at load and
	defers four — `Chip`, `VirtualList`, `VirtualGrid`, `AsyncImage` — into the
	closure that builds them, so a game that builds none never compiles them
	(repeated separate-process rounds paired by index, re-reproduced at review:
	228 KB [131..313] of Lua heap). Two claims ride
	on that and both need an instrument: WHICH four are deferred, and WHERE the load
	happens — a construction seam, once, never inside a frame.

	THE FIRST VERSION OF THIS PIN COULD NOT FAIL. It asserted
	`rawequal(require(m), require(m))` across a scroll, which the module cache makes
	true whether or not anything is deferred, and that `preload()` returned 4 twice,
	which a body of `return 4` satisfies. Both mutations — re-eagerising the four,
	and gutting `preload` — left the suite fully green. The lesson is that the module
	cache defeats every identity-of-the-module test written from outside: a second
	`require` is a table lookup, so "the module is the same object" is a fact about
	the cache and never about this file.

	SO THE INSTRUMENT WATCHES THE CALL, NOT THE CACHE. `src/init.luau` is loaded a
	second time through `luau.load` with an environment whose `require` is a
	recorder: it logs the path, delegates to the real `require` (which resolves from
	the cache, so nothing is loaded twice and nothing is measured in time), and hands
	the module back. Every `require` the file performs is then visible — at load, at
	construction, or inside a frame — and the deferred SET is derived by subtracting
	what the load asked for from what the source names, so a fifth deferral joins the
	pin by itself instead of escaping a hand-written list.

	WHAT IT DOES NOT SEE, stated so nobody reads it wider than it is: only requires
	made BY `src/init.luau`. A control module's own internal requires run under the
	real global and are invisible here — this pins the framework's own deferral seam,
	which is the thing the four entries and `preload` are a claim about.

	The sandboxed copy shares every dependency with the real one (the recorder
	delegates to the same cached `require`), so `probe.module.newCore()`,
	`probe.module.UI` and the real `mountLib` are the same modules the suite uses
	everywhere else. ]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local INIT_SOURCE_PATH = "src/init.luau"

type RequireCall = { path: string, module: any }

local function loadInitUnderRecordingRequire(): any
	local log: { RequireCall } = {}
	local realRequire = require
	local function recorder(path: string): any
		--[[ `src/init.luau` requires ONLY through the `@self/` alias, which resolves
			against ITS folder; from this spec that same folder is `../src/`. Any other
			spelling would be silently mis-resolved, so it errors rather than guesses. ]]
		local rel, replaced = string.gsub(path, "^@self/", "../src/")
		assert(replaced == 1, `laziness recorder: unexpected require spelling '{path}'`)
		local module = (realRequire :: any)(rel)
		table.insert(log, { path = path, module = module })
		return module
	end

	local chunk = luau.load(fs.readFile(INIT_SOURCE_PATH), {
		debugName = INIT_SOURCE_PATH,
		environment = { require = recorder } :: any,
		injectGlobals = true,
	})
	local probe: any = {}
	probe.module = (chunk :: any)()
	probe.atLoad = {}
	for _, call in log do
		table.insert(probe.atLoad, call.path)
	end

	-- every `require` the file performs while `fn` runs, in order
	function probe.record(fn: () -> ()): { RequireCall }
		local from = #log
		fn()
		local out: { RequireCall } = {}
		for i = from + 1, #log do
			table.insert(out, log[i])
		end
		return out
	end

	-- the DEFERRED set, derived: every `@self/` module the source names, minus
	-- every one the load actually asked for
	function probe.deferred(): { string }
		local atLoad: { [string]: boolean } = {}
		for _, path in probe.atLoad do
			atLoad[path] = true
		end
		local out: { string } = {}
		local seen: { [string]: boolean } = {}
		for path in string.gmatch(fs.readFile(INIT_SOURCE_PATH), 'require%("(@self/[^"]+)"%)') do
			if not atLoad[path] and not seen[path] then
				seen[path] = true
				table.insert(out, path)
			end
		end
		table.sort(out)
		return out
	end
	return probe
end

-- the recorded paths, sorted and joined, so a failure prints the whole set
local function pathsOf(calls: { RequireCall }): string
	local out: { string } = {}
	for _, call in calls do
		table.insert(out, call.path)
	end
	table.sort(out)
	return table.concat(out, " ")
end

local function listSpec(probe: any, rows: any): any
	return {
		id = "VL",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = 40,
		viewportHeight = 400,
		overscan = 2,
		cell = function(item: any)
			return probe.module.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
	}
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

	--[[ AN OFF-WINDOW EDIT THAT MOVES NOTHING MUST DIRTY NOTHING (review RR-5,
		measured wave T15).

		The review's claim was general — "memos returning a fresh table with default
		identity eq notify on every recompute, re-dirtying measure/arrange for
		unchanged values, 25 sites" — and the measurement found exactly one shipped
		memo where it costs a re-solve rather than nothing: the virtual canvas Dim.
		It is `{ type = "fixed", px = index.content }`, rebuilt whenever the layout
		index recomputes, and a table literal is never identity-equal to the previous
		one — so an edit to a row nobody is looking at, in a list whose LENGTH did not
		change, republished a Dim holding the same number and the surface re-solved.

		Measured before the fix (tools/lune/_probe_t15_rr5, 40 iterations of the
		perf lab's own collection churn): 41 solves against 1, all forty of the extra
		ones producing zero rect writes and zero prop writes. Three more lab
		workloads moved with it — `variable-extents` 294 -> 246, `edit-locality`
		131 -> 83 (its partial solves 53 -> 29), `collection-churn` 30 -> 25.

		The window's KEY SEQUENCE is deliberately left alone here (the edit is at row
		50 of 100 with a viewport of ten), so nothing structural is expected either —
		and asserting both is what stops a future "fix" that buys the arrange back by
		making the window deaf. ]]
	it("an off-window edit that changes no key and no extent dirties NOTHING (RR-5)", function()
		local core = Facet.newCore()
		local items = makeRows(100)
		local rows = core:signal(items)
		local list = newList(core, { rows = rows })
		local root = mountLib.mount(core, list.blueprint)
		root.takeDirty()

		-- row 50 is far outside the mounted window (10 visible + 2 overscan), and
		-- the list keeps its length, so the canvas extent is the number it already
		-- was. Same key, new payload: the only honest "nothing moved" edit.
		local next = table.clone(items)
		next[50] = { id = "r50", label = "Row 50 (edited off-window)" }
		rows:set(next)

		local dirty: { string } = {}
		for _, entry in root.takeDirty() do
			table.insert(dirty, entry.class)
		end
		expect(table.concat(dirty, ",")).toBe("")
		root.dispose()
	end)

	--[[ A DEFERRED REQUIRE FIRES AT CONSTRUCTION, NEVER IN A FRAME (wave T15).

		Three pins over one instrument (`loadInitUnderRecordingRequire`, above): the
		SET that is deferred, the SEAM the load happens at, and what `preload` does.
		Each of them fails on the mutation it names — re-eagerising the four reddens
		the first, moving a `require` into a scroll path reddens the second, and
		gutting `preload`'s body reddens the third. ]]
	it("requiring Facet loads the fifteen typed controls and defers exactly four (T15)", function()
		local probe = loadInitUnderRecordingRequire()

		--[[ POSITIVE CONTROL, FIRST. A recorder wired to nothing would satisfy every
			"was not required" assertion below for the wrong reason, which is precisely
			the failure this pin replaces. Loading the file requires the fifteen typed
			controls, and `Table` and `RowActions` are two of them. ]]
		expect(#probe.atLoad >= 40).toBe(true)
		expect(table.find(probe.atLoad, "@self/controls/table") ~= nil).toBe(true)
		expect(table.find(probe.atLoad, "@self/controls/row_actions") ~= nil).toBe(true)

		--[[ ...and the four that declare no spec type are absent from it. Derived
			from the source rather than listed here, so the day a fifth control is
			deferred this line moves with it instead of quietly not covering it. ]]
		expect(table.concat(probe.deferred(), " ")).toBe(
			"@self/controls/async_image @self/controls/chip "
				.. "@self/controls/virtual_grid @self/controls/virtual_list"
		)
	end)

	it("the deferred require fires at the construction seam and never in a frame (T15)", function()
		local probe = loadInitUnderRecordingRequire()
		local core = probe.module.newCore()
		local rows = core:signal(makeRows(500))

		-- THE SEAM: building the control is what loads it, and it loads nothing else
		local list: any = nil
		local atConstruction = probe.record(function()
			list = probe.module.Controls.VirtualList(core, listSpec(probe, rows))
		end)
		expect(pathsOf(atConstruction)).toBe("@self/controls/virtual_list")

		-- mounting is construction too, and by now the module is already in hand
		local root: any = nil
		local atMount = probe.record(function()
			root = mountLib.mount(core, list.blueprint)
		end)
		expect(pathsOf(atMount)).toBe("")

		--[[ ...AND THE STEADY STATE, which must load nothing at all. Thirty scroll
			steps, a window slide and an off-window data edit: a `require` moved into
			any of those paths is a module compile in the middle of a frame, and it
			would show up here as a path this list does not have. ]]
		local inSteadyState = probe.record(function()
			for i = 1, 30 do
				list.scrollTop:set(i * 37)
			end
			local nextRows = table.clone(rows:get() :: { any })
			nextRows[400] = { id = "r400", label = "edited off-window" }
			rows:set(nextRows)
		end)
		expect(pathsOf(inSteadyState)).toBe("")
		root.dispose()
	end)

	it("Facet.preload() force-loads exactly the deferred set, and twice is a cache hit (T15)", function()
		local probe = loadInitUnderRecordingRequire()
		local deferred = table.concat(probe.deferred(), " ")
		expect(deferred).never().toBe("")

		local reported: number = -1
		local firstCall = probe.record(function()
			reported = probe.module.preload()
		end)
		--[[ THE SET, NOT THE COUNT. `preload` has to ask for every path the Controls
			table defers and for no other; a body that returns the right number without
			requiring anything is the mutation this replaces. ]]
		expect(pathsOf(firstCall)).toBe(deferred)
		-- ...and the number it reports is the number it actually required
		expect(reported).toBe(#firstCall)

		--[[ THE MODULES IT LOADED ARE THE ONES THE CLOSURES USE — the half a count
			cannot say. A `preload` naming a different spelling of the same file would
			resolve to a different table, and this is where that shows. ]]
		local preloadedList: any = nil
		for _, call in firstCall do
			if call.path == "@self/controls/virtual_list" then
				preloadedList = call.module
			end
		end
		local core = probe.module.newCore()
		local built = probe.record(function()
			probe.module.Controls.VirtualList(core, listSpec(probe, core:signal(makeRows(4))))
		end)
		expect(#built).toBe(1)
		expect(rawequal(built[1].module, preloadedList)).toBe(true)

		-- IDEMPOTENT: the second call asks the same four questions, `require`'s own
		-- cache answers them, and the reported count does not drift
		local secondCall = probe.record(function()
			expect(probe.module.preload()).toBe(reported)
		end)
		expect(pathsOf(secondCall)).toBe(deferred)
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
