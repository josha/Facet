--!strict
--[[
	VARIABLE ITEM EXTENTS — `newVirtualList.itemExtent` as a per-item function.

	THE MEASUREMENT THAT BOUGHT THIS (ruling 7, ruled 2026-08-13). The widened
	overflow sweep — 42 surfaces x 8 viewports x 4 text preferences — found a
	`row_actions` row declaring `itemExtent = 84` and measuring 88 at the DEFAULT
	text preference, and 249 on a 320x640 phone at `preferredTextOffset = 14`.
	`index x itemExtent` is O(1) and exact only because the extent is one number,
	so the control made the CONSUMER predict its own row's height for every live
	fact the row reads; the perf lab's own `heightFor` learned four of those inputs
	one post-mortem at a time. A list whose rows differ — because the text
	preference grew them, because localization expanded them ~1.4x, or because the
	items simply are not the same shape — could not be expressed at all.

	WHAT THIS SPEC PINS:

	  · the ARITHMETIC moves to a running-offset index (`src/virtual_extents.luau`,
	    proved on its own in `virtual_extents.spec`) — here we prove the CONTROL
	    is wired to it: row boxes, canvas extent, window membership, keep-visible,
	    the insertion slot and the per-row slot declaration all agree with it;
	  · VIRTUALIZATION STAYS BOUNDED. The window is bounded on a 10,000-item
	    ragged list, and — the property that actually matters — only the windowed
	    items are ever BUILT. An implementation that built or measured every row to
	    lay out the list would be a right answer that deletes the reason the
	    control exists;
	  · SCROLL POSITION STAYS STABLE. When the extents re-derive under the player
	    (the accessibility case: every row grows at once), the item at the top of
	    the viewport stays at the top. This repo has a recorded jump class from
	    exactly this shape;
	  · THE UNIFORM PATH IS UNTOUCHED. A variable list whose function returns one
	    constant is proved IDENTICAL to the uniform list it replaces — same window,
	    same rects, same canvas — so the general mechanism contains the special
	    case rather than resembling it.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local mountLib = require("../src/mount")
local fake_target = require("../tests/lib/fake_target")
local virtual_extents = require("../src/virtual_extents") :: any

local function makeRows(n: number): { { id: string, label: string } }
	local rows = {}
	for i = 1, n do
		table.insert(rows, { id = `r{i}`, label = `Row {i}` })
	end
	return rows
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

local function newList(core: any, opts: any)
	return virtual_list.build(Facet, core, {
		id = "VL",
		rows = opts.rows,
		key = function(item: any)
			return item.id
		end,
		itemExtent = opts.itemExtent,
		rowGap = opts.rowGap,
		viewportExtent = opts.viewportExtent or 498,
		overscan = opts.overscan or 2,
		reorderable = opts.reorderable,
		onReorder = opts.onReorder,
		cell = opts.cell or function(item: any)
			return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
	})
end

-- a PRESENTED list, so the real solver gives rects to measure row boxes against
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
		itemExtent = opts.itemExtent,
		rowGap = opts.rowGap,
		viewportExtent = opts.viewportExtent,
		overscan = opts.overscan,
		reorderable = opts.reorderable,
		onReorder = opts.onReorder,
		cell = opts.cell,
	})
	local screen = Facet.UI.Screen({ id = "S", children = { list.blueprint } })
	local handle = pres.present(screen)
	pres.refresh()
	list.bindNativeScroll(handle.controller)
	local w: any = { core = core, list = list, rows = rows, adapter = adapter, handle = handle, pres = pres }
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
	return w
end

-- the shape the ruling names: four rows of 84 with one that grew to 249 under
-- the largest text preference
local RAGGED = { 84, 249, 84, 120 }
local function raggedExtent(_item: any, index: number): number
	return RAGGED[(index - 1) % #RAGGED + 1]
end

describe("VirtualList variable extents: what the spec accepts", function()
	it("accepts a per-item function, and the dump says which arithmetic is running", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(6))
		local list = newList(core, { rows = rows, itemExtent = raggedExtent })
		local d = list.dump()
		expect(d.itemExtentMode).toBe("variable")
		-- there is no ONE extent to report, so the field that used to carry it is
		-- absent rather than lying, and the total the canvas spans is reported
		expect(d.itemExtent).toBe(nil)
		expect(d.rowHeight).toBe(nil)
		expect(d.contentExtent).toBe(84 + 249 + 84 + 120 + 84 + 249)
		list.dispose()
	end)

	it("a uniform list still reports its one number, and says so", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(6))
		local list = newList(core, { rows = rows, itemExtent = 56 })
		local d = list.dump()
		expect(d.itemExtentMode).toBe("uniform")
		expect(d.itemExtent).toBe(56)
		expect(d.rowHeight).toBe(56)
		expect(d.contentExtent).toBe(6 * 56)
		list.dispose()
	end)

	it("refuses a per-item extent that is not a positive number, naming the row", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(4))
		local function build(fn: any)
			local list = newList(core, { rows = rows, itemExtent = fn })
			-- the extents resolve lazily with the index memo; asking for the window
			-- is what forces them
			list.dump()
			list.dispose()
		end
		local ok, err = pcall(build, function(_item: any, index: number)
			return if index == 3 then 0 else 56
		end)
		expect(ok).toBe(false)
		-- the message has to name WHICH row, or a 10,000-row list is a scavenger hunt
		expect(string.find(tostring(err), "r3", 1, true) ~= nil).toBe(true)
		expect(pcall(build, function()
			return "56"
		end)).toBe(false)
		expect(pcall(build, function()
			return -1
		end)).toBe(false)
		-- ...and the legal one still builds
		expect(pcall(build, raggedExtent)).toBe(true)
	end)
end)

describe("VirtualList variable extents: the geometry is the running offset", function()
	it("each row's box is its OWN extent, at the prefix-sum offset", function()
		local w = world({ rows = makeRows(4), itemExtent = raggedExtent, viewportExtent = 600 })
		local r1, r2, r3, r4 = w.rect("r1"), w.rect("r2"), w.rect("r3"), w.rect("r4")
		expect(r1.h).toBe(84)
		expect(r2.h).toBe(249)
		expect(r3.h).toBe(84)
		expect(r4.h).toBe(120)
		expect(r2.y - r1.y).toBe(84)
		expect(r3.y - r1.y).toBe(84 + 249)
		expect(r4.y - r1.y).toBe(84 + 249 + 84)
	end)

	it("the gutter is dead space between ragged slots, exactly as it is uniform ones", function()
		local w = world({ rows = makeRows(3), itemExtent = raggedExtent, rowGap = 6, viewportExtent = 600 })
		local r1, r2, r3 = w.rect("r1"), w.rect("r2"), w.rect("r3")
		expect(r2.y - (r1.y + r1.h)).toBe(6)
		expect(r3.y - (r2.y + r2.h)).toBe(6)
		expect(r2.h).toBe(249)
	end)

	it("the content extent is the sum plus the gutters, with none trailing", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(4))
		local list = newList(core, { rows = rows, itemExtent = raggedExtent, rowGap = 6, viewportExtent = 200 })
		list.bindNativeScroll(scrollStub(), "/VL")
		-- the scroll clamp is the whole truth about the content extent
		list.scrollTop:set(100000)
		expect(list.dump().scrollTop).toBe(84 + 249 + 84 + 120 + 3 * 6 - 200)
		list.dispose()
	end)

	it("the PAINTED canvas spans the running total, not count x one extent", function()
		--[[ THE CANVAS IS THE HALF THE ENGINE READS. The framework's scroll CLAMP and
			the ScrollingFrame's `CanvasSize` are two different consumers of the same
			number, and only this one is visible to the player's finger: a canvas that
			spans `count × oneExtent` lets the engine scroll somewhere the framework
			refuses to window. Asserted on the SOLVED box, not on the memo. ]]
		local w = world({ rows = makeRows(4), itemExtent = raggedExtent, rowGap = 6, viewportExtent = 200 })
		local canvas = w.handle.controller.rectOf("/S/VL/Canvas")
		expect(canvas ~= nil).toBe(true)
		expect(canvas.h).toBe(84 + 249 + 84 + 120 + 3 * 6)
	end)

	it("keep-visible measures the row's OWN extent, not an average", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(8))
		local list = newList(core, { rows = rows, itemExtent = raggedExtent, viewportExtent = 300 })
		local ctrl = scrollStub()
		list.bindNativeScroll(ctrl, "/VL")
		-- row 6 is a 249 (index 6 -> RAGGED[2]); its slot starts at
		-- 84+249+84+120+84 = 621, and the minimal downward scroll parks its bottom
		-- on the band's bottom edge
		list.focusKey("r6")
		expect(ctrl.lastPos().y).toBe(621 + 249 - 300)
		list.focusKey("r1")
		expect(ctrl.lastPos().y).toBe(0)
		list.dispose()
	end)
end)

describe("VirtualList variable extents: virtualization stays bounded", function()
	it("a viewport inside ONE tall row windows that row alone", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(40))
		local list = newList(core, { rows = rows, itemExtent = raggedExtent, viewportExtent = 120, overscan = 0 })
		-- row 2 spans 84..333; a 120px viewport parked at 100 is entirely inside it
		list.scrollTop:set(100)
		expect(list.dump().window).toEqual({ "r2" })
		list.dispose()
	end)

	it("only the WINDOWED items are ever built — 10,000 ragged rows, bounded", function()
		--[[ THE PROPERTY THE WHOLE DESIGN IS ABOUT. "Measure every item at mount"
			is one of the two candidate designs the parity doc recorded, and this is
			the check that refuses it: a build counter, not a timer. Two candidate
			designs, and the one that pays O(N) MEASUREMENT cannot pass this. ]]
		local core = Facet.newCore()
		local rows = core:signal(makeRows(10000))
		local built = 0
		local list = newList(core, {
			rows = rows,
			itemExtent = raggedExtent,
			viewportExtent = 498,
			cell = function(item: any)
				built += 1
				return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
			end,
		})
		local root = mountLib.mount(core, list.blueprint)
		expect(built < 30).toBe(true)
		local atTop = built
		-- a deep jump windows a new band and builds only that band
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
end)

describe("VirtualList variable extents: the scroll does not jump when extents change", function()
	it("the item at the top of the viewport stays at the top", function()
		--[[ THE ACCESSIBILITY CASE, run forwards. Every row grows at once because
			the player raised the text preference. Without an anchor the canvas
			lengthens under a fixed pixel offset and the player is somewhere else in
			the list — the recorded jump class. The anchor is the item under the
			viewport's leading edge, and the offset INTO it. ]]
		local core = Facet.newCore()
		local rows = core:signal(makeRows(200))
		local grow = core:signal(0)
		local list = newList(core, {
			rows = rows,
			viewportExtent = 400,
			itemExtent = function(_item: any, _index: number, use: any): number
				return 56 + use(grow)
			end,
		})
		local ctrl = scrollStub()
		list.bindNativeScroll(ctrl, "/VL")
		-- park row 21 exactly at the top of the viewport, then 10px into row 21
		ctrl.scrollTo("/VL", { x = 0, y = 20 * 56 + 10 })
		expect(list.dump().window[3]).toBe("r21")
		-- the preference moves: every row is 28px taller
		grow:set(28)
		-- row 21 now starts at 20*84; the anchor keeps the same 10px into it
		expect(ctrl.lastPos().y).toBe(20 * 84 + 10)
		expect(list.dump().scrollTop).toBe(20 * 84 + 10)
		list.dispose()
	end)

	--[[ THE END-OF-LIST SHRINK, which `controls/table.luau` measured and fixed and
		this control did not have (reuse audit 2026-08-17). The anchor observer
		compared its target against `clampedTop` — a MEMO over the index — instead
		of against `scrollTop`, the raw engine mirror. Hard against the end of a
		list whose items then SHRINK, the memo has already clamped itself to the new
		maximum while the engine's real `CanvasPosition` is still far past the last
		item, so the two agree, nothing is written, and the player is left looking
		at blank space. Measured on the Table at 400 rows shrinking 43 -> 40px: the
		engine sat 1,200px out of range.

		The instrument is the SCROLL STUB, because the defect is exactly "no write
		was made": `lastPos()` is what the framework actually told the engine. ]]
	it("shrinking the items at the END of the list still corrects the ENGINE, not just the memo", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(200))
		local grow = core:signal(28)
		local list = newList(core, {
			rows = rows,
			viewportExtent = 400,
			itemExtent = function(_item: any, _index: number, use: any): number
				return 56 + use(grow)
			end,
		})
		local ctrl = scrollStub()
		list.bindNativeScroll(ctrl, "/VL")
		-- hard against the end: 200 items at 84px, a 400px viewport
		local content = 200 * 84
		ctrl.scrollTo("/VL", { x = 0, y = content - 400 })
		expect(list.dump().scrollTop).toBe(content - 400)

		-- every item shrinks back to 56px: the content is now 11,200 and the
		-- engine is 5,600px past the end of it
		grow:set(0)
		local corrected = ctrl.lastPos().y
		-- THE ASSERTION THE OLD COMPARISON FAILED: a write happened at all, and it
		-- landed inside the new content
		expect(corrected <= 200 * 56 - 400 + 0.5).toBe(true)
		expect(corrected < content - 400).toBe(true)
		list.dispose()
	end)

	it("the extents re-derive through `use`, and the canvas follows", function()
		local core = Facet.newCore()
		local rows = core:signal(makeRows(4))
		local grow = core:signal(0)
		local list = newList(core, {
			rows = rows,
			viewportExtent = 400,
			itemExtent = function(_item: any, index: number, use: any): number
				return (if index == 2 then 100 else 50) + use(grow)
			end,
		})
		expect(list.dump().contentExtent).toBe(50 + 100 + 50 + 50)
		grow:set(10)
		expect(list.dump().contentExtent).toBe(60 + 110 + 60 + 60)
		list.dispose()
	end)
end)

describe("VirtualList variable extents: the rest of the control agrees with the index", function()
	it("the insertion slot snaps on ragged midpoints", function()
		local moves: { any } = {}
		local w = world({
			rows = makeRows(6),
			itemExtent = raggedExtent,
			viewportExtent = 700,
			reorderable = true,
			onReorder = function(key: string, toIndex: number)
				table.insert(moves, { key = key, toIndex = toIndex })
			end,
		})
		local path = w.hitPath("r1")
		w.adapter.driveDragStart(path, { x = 100, y = w.rowY("r1"), pointerType = "mouse" })
		w.adapter.driveDragContinue(path, { x = 100, y = w.rowY("r1") + 10, pointerType = "mouse" }, { x = 0, y = 0 })
		-- row 2 is the 249: its midpoint is at canvas 84 + 124.5 = 208.5, so a
		-- pointer just above it is still slot 1 and just below it is slot 2
		local r2 = w.rect("r2")
		w.adapter.driveDragContinue(path, { x = 100, y = r2.y + 120, pointerType = "mouse" }, { x = 0, y = 0 })
		expect(w.list.dropIndex:get()).toBe(1)
		w.adapter.driveDragContinue(path, { x = 100, y = r2.y + 130, pointerType = "mouse" }, { x = 0, y = 0 })
		expect(w.list.dropIndex:get()).toBe(2)
	end)

	it("the declared slot is PER ROW: the guard names that row's own number", function()
		--[[ The lying-`itemExtent` guard stays, and it gets sharper: it now compares
			each row against ITS OWN declaration instead of one list-wide number, so a
			consumer who under-declares exactly one row is told about exactly that row.
			(It is not deleted by this feature: a row can still exceed a declared
			extent — this test IS that case.) ]]
		local w = world({
			rows = makeRows(3),
			viewportExtent = 600,
			itemExtent = function(_item: any, index: number): number
				return if index == 2 then 20 else 200
			end,
			cell = function(item: any)
				return Facet.UI.Box({ id = "Plate", height = { type = "fixed", px = 60 } })
			end,
		})
		local found = nil
		for _, d in w.handle.controller.diagnostics() do
			if string.find(d.issue, "itemExtent", 1, true) ~= nil then
				found = d
			end
		end
		expect(found ~= nil).toBe(true)
		-- 20 declared, 60 measured — the row's OWN number, not the list's first
		expect(string.find(tostring((found :: any).issue), "itemExtent = 20", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring((found :: any).node), "r2", 1, true) ~= nil).toBe(true)
	end)
end)

describe("VirtualList variable extents: an edit that moves no geometry rebuilds nothing", function()
	--[[ THE INDEX IS SIX CLOSURES AND A TABLE, and everything downstream of it —
		the canvas, the clamp, the window, every mounted row's offset — dirties when
		it changes identity. A list is EDITED far more often than its geometry moves
		(a rename, a live value ticking, a re-sort of equal-height rows), so an index
		rebuilt on every edit would be a tax every shipped list pays for a feature
		most of them do not use.

		COUNTED, NOT TIMED, for the reason the boundedness case is: the headless perf
		runner's own A/A control on these scenes measures a ±5%..±28% noise band,
		which is wider than one allocation per edit could ever move. The constructor
		is wrapped here rather than inferred from a clock. ]]
	local function countingExtents<T>(body: (counts: { uniform: number, variable: number }) -> T): T
		local counts = { uniform = 0, variable = 0 }
		local realUniform, realVariable = virtual_extents.uniform, virtual_extents.variable
		local ok, result = pcall(function()
			virtual_extents.uniform = function(...)
				counts.uniform += 1
				return realUniform(...)
			end
			virtual_extents.variable = function(...)
				counts.variable += 1
				return realVariable(...)
			end
			return body(counts)
		end)
		virtual_extents.uniform, virtual_extents.variable = realUniform, realVariable
		if not ok then
			error(result, 0)
		end
		return result :: any
	end

	it("a uniform list rebuilds its index only when the geometry moves", function()
		countingExtents(function(counts)
			local core = Facet.newCore()
			local rows = core:signal(makeRows(20))
			local extent = core:signal(56)
			local list = newList(core, { rows = rows, itemExtent = extent, viewportExtent = 300 })
			list.dump() -- force the first build
			local built = counts.uniform
			expect(built > 0).toBe(true)
			-- a RENAME: same count, same extent, same gap — nothing about the
			-- geometry moved, so the index must not be rebuilt
			local renamed = makeRows(20)
			renamed[3].label = "renamed"
			rows:set(renamed)
			list.dump()
			expect(counts.uniform).toBe(built)
			-- ...and the things that DO move it, do
			rows:set(makeRows(21))
			list.dump()
			expect(counts.uniform).toBe(built + 1)
			extent:set(84)
			list.dump()
			expect(counts.uniform).toBe(built + 2)
			list.dispose()
			return true
		end)
	end)

	it("a variable list rebuilds only when an EXTENT moves, not when an item does", function()
		countingExtents(function(counts)
			local core = Facet.newCore()
			local rows = core:signal(makeRows(20))
			local list = newList(core, { rows = rows, itemExtent = raggedExtent, viewportExtent = 300 })
			list.dump()
			local built = counts.variable
			expect(built > 0).toBe(true)
			-- the extents are a function of the INDEX here, so a rename leaves every
			-- one of them where it was
			local renamed = makeRows(20)
			renamed[7].label = "renamed"
			rows:set(renamed)
			list.dump()
			expect(counts.variable).toBe(built)
			-- ...and one more row is one more extent
			rows:set(makeRows(21))
			list.dump()
			expect(counts.variable).toBe(built + 1)
			list.dispose()
			return true
		end)
	end)
end)

describe("VirtualList variable extents: the uniform path is untouched", function()
	it("a per-item function returning one constant is IDENTICAL to the uniform list", function()
		--[[ THE DIFFERENTIAL ORACLE. Two lists, same data, same viewport, same gap:
			one declares `itemExtent = 56`, the other a function that returns 56. Every
			observable has to agree at every scroll offset — window membership, canvas
			extent, keep-visible target, row rects — or the general mechanism does not
			contain the special case it replaces. ]]
		local uniform = world({ rows = makeRows(40), itemExtent = 56, rowGap = 6, viewportExtent = 300 })
		local variable = world({
			rows = makeRows(40),
			itemExtent = function()
				return 56
			end,
			rowGap = 6,
			viewportExtent = 300,
		})
		-- SLOT-ALIGNED offsets, where the two window rules are the same rule. The
		-- one place they deliberately differ — mid-slot, where the uniform rule's
		-- offset-independent visible COUNT names one row fewer than the viewport
		-- touches — is pinned in `virtual_extents.spec`, and is asserted below to be
		-- the ONLY difference.
		for _, top in { 0, 62, 620, 1240, 100000 } do
			uniform.list.scrollTop:set(top)
			variable.list.scrollTop:set(top)
			local u, v = uniform.list.dump(), variable.list.dump()
			expect(v.window).toEqual(u.window)
			expect(v.scrollTop).toBe(u.scrollTop)
			expect(v.contentExtent).toBe(u.contentExtent)
		end
		-- ...and mid-slot the variable window is a strict SUPERSET: same first row,
		-- one more at the end, never a row the uniform list mounted and this one did
		-- not
		for _, top in { 1, 31, 100, 1000 } do
			uniform.list.scrollTop:set(top)
			variable.list.scrollTop:set(top)
			local u, v = uniform.list.dump(), variable.list.dump()
			expect(v.window[1]).toBe(u.window[1])
			expect(#v.window - #u.window <= 1).toBe(true)
			expect(#v.window >= #u.window).toBe(true)
			expect(v.scrollTop).toBe(u.scrollTop)
			expect(v.contentExtent).toBe(u.contentExtent)
		end
		uniform.list.scrollTop:set(0)
		variable.list.scrollTop:set(0)
		uniform.pres.refresh()
		variable.pres.refresh()
		for _, key in { "r1", "r2", "r3" } do
			local a, b = uniform.rect(key), variable.rect(key)
			expect(`{b.y}|{b.h}`).toBe(`{a.y}|{a.h}`)
		end
	end)
end)
