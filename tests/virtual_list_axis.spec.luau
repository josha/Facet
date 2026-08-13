--!strict
--[[
	`newVirtualList.axis` — THE SIDEWAYS VIRTUALIZER
	(docs/plans/swiftui-parity-round2.md §2.3; game-director decision 2026-08-12).

	`newVirtualList` is the ONE lazy-collection surface in this framework — no
	`LazyVStack`/`LazyHStack` constructor ships — and until now it was
	vertical-only. `axis = "y" | "x"` (default `"y"`, construction-only for the
	reason `ScrollView.axis` is construction-only: constitution §16 E-6) gives it
	the second axis.

	THE ARITHMETIC IS NOT THE WORK. `index × pitch` is `index × pitch` whichever
	way the list runs; what this spec pins is everything that quietly assumed
	"down":

	  · NAMING. `itemExtent` / `viewportExtent` are the canonical, axis-neutral
	    names. `rowHeight` / `viewportHeight` are DEPRECATED ALIASES that keep
	    working unchanged (ADR-0011, ≥ one MINOR, registered in
	    `LuauUI.DEPRECATIONS`) — the cases below prove an existing vertical caller
	    passing the old names is untouched, and that passing a name AND its alias
	    is refused rather than silently resolved.
	  · THE ENGINE COORDINATE. A horizontal list mirrors `CanvasPosition.X`,
	    declares a full-WIDTH canvas, and writes its keep-visible / autoscroll /
	    drop-line targets on x. Reading the wrong component is the defect this
	    file's discriminators are aimed at: a list that scrolls one way and
	    windows the other.
	  · FOCUS. The contributed group declares the LIST'S axis, so Navigate maps to
	    Left/Right — ONE focus map read two ways (constitution §9), never a second
	    order.
	  · ROW ACTIONS ARE REFUSED. A tray is opened by a sideways swipe, and on a
	    sideways list a sideways swipe is already the scroll gesture.

	Variable item extents are OUT OF SCOPE and are a recorded gap, not a seam:
	nothing here is staged for them.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local fake_target = require("../tests/lib/fake_target")

local function makeRows(n: number): { { id: string, label: string } }
	local rows = {}
	for i = 1, n do
		table.insert(rows, { id = `r{i}`, label = `Row {i}` })
	end
	return rows
end

-- a controller-shaped scroll stub (virtualization.spec's own seam): the headless
-- stand-in for the engine moving CanvasPosition. It records the FULL {x,y} it was
-- written, which is the discriminator every axis case below turns on.
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

-- a headless list: no presenter, so the arithmetic answers on its own
local function newList(core: any, opts: any)
	local spec: any = {
		id = "VL",
		rows = opts.rows,
		key = function(item: any)
			return item.id
		end,
		axis = opts.axis,
		rowGap = opts.rowGap,
		overscan = opts.overscan or 2,
		cell = function(item: any)
			return LuauUI.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
	}
	-- the two spellings, exactly as a caller would write one or the other
	if opts.legacyNames then
		spec.rowHeight = opts.itemExtent or 40
		spec.viewportHeight = opts.viewportExtent or 400
	else
		spec.itemExtent = opts.itemExtent or 40
		spec.viewportExtent = opts.viewportExtent or 400
	end
	return virtual_list.build(LuauUI, core, spec)
end

-- a PRESENTED list, so the real solver hands back rects and a scroll region
local function world(opts: any?)
	local options = opts or {}
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system)
	local rows = core:signal(makeRows(options.count or 100))
	local activations: { any } = {}
	local reorders: { any } = {}
	local spec: any = {
		id = "VL",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		axis = options.axis,
		rowGap = options.rowGap,
		overscan = options.overscan or 2,
		reorderable = options.reorderable,
		onReorder = if options.reorderable
			then function(key: string, toIndex: number)
				table.insert(reorders, { key = key, toIndex = toIndex })
			end
			else nil,
		autoscroll = options.autoscroll,
		cell = function(item: any)
			return LuauUI.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
		onActivate = function(item: any, meta: any)
			table.insert(activations, { item = item, meta = meta })
		end,
	}
	if options.legacyNames then
		spec.rowHeight = options.itemExtent or 40
		spec.viewportHeight = options.viewportExtent or 400
	else
		spec.itemExtent = options.itemExtent or 40
		spec.viewportExtent = options.viewportExtent or 400
	end
	local list = virtual_list.build(LuauUI, core, spec)
	local handle = pres.present(LuauUI.UI.Screen({ id = "S", children = { list.blueprint } }))
	pres.refresh()
	local unbindScroll = list.bindNativeScroll(handle.controller)
	local w: any = {
		core = core,
		system = system,
		adapter = adapter,
		pres = pres,
		list = list,
		rows = rows,
		handle = handle,
		activations = activations,
		reorders = reorders,
		unbindScroll = unbindScroll,
	}
	function w.hitPath(key: string): string
		return `/S/VL/Canvas/W/[{key}]/Row/Hit`
	end
	function w.rect(key: string): any
		return handle.controller.rectOf(w.hitPath(key))
	end
	function w.hostRect(): any
		return handle.controller.rectOf("/S/VL")
	end
	function w.registry(): any
		return handle.controller.dragRegistry()
	end
	-- a MOUSE lift on a horizontal list: the promotion travel is along x, which
	-- is also the axis the drop slot is read on
	function w.liftX(key: string)
		local r = w.rect(key)
		local x, y = r.x + r.w / 2, r.y + r.h / 2
		adapter.driveDragStart(w.hitPath(key), { x = x, y = y, pointerType = "mouse" })
		adapter.driveDragContinue(w.hitPath(key), { x = x + 12, y = y, pointerType = "mouse" }, { x = 0, y = 0 })
	end
	function w.moveToX(key: string, x: number)
		local r = w.rect(key) or w.rect("r1")
		adapter.driveDragContinue(w.hitPath(key), { x = x, y = r.y + r.h / 2, pointerType = "mouse" }, { x = 0, y = 0 })
	end
	function w.releaseX(key: string, x: number)
		local r = w.rect(key) or w.rect("r1")
		adapter.driveDragEnd(w.hitPath(key), { x = x, y = r.y + r.h / 2, pointerType = "mouse" })
	end
	-- the diagnostic every fixture owes (docs/lessons/the-solver-already-told-you.md)
	function w.diagnostics(): { any }
		return handle.controller.diagnostics()
	end
	return w
end

-- ===========================================================================
describe('VirtualList.axis — the contract ("y" | "x", construction-only)', function()
	it('defaults to "y", accepts "y" explicitly, and refuses anything else naming BOTH values', function()
		local core = LuauUI.newCore()
		local rows = core:signal(makeRows(8))
		local default = newList(core, { rows = rows })
		expect(default.dump().axis).toBe("y")
		local explicit = newList(core, { rows = rows, axis = "y" })
		expect(explicit.dump().axis).toBe("y")
		local sideways = newList(core, { rows = rows, axis = "x" })
		expect(sideways.dump().axis).toBe("x")

		local ok, err = pcall(function()
			newList(core, { rows = rows, axis = "horizontal" })
		end)
		expect(ok).toBe(false)
		-- the refusal names both legal values AND why it is construction-only:
		-- a message that only says "invalid" gets guessed at
		expect(string.find(tostring(err), "horizontal", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), 'must be "y"', 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "construction-only", 1, true) ~= nil).toBe(true)
		default.dispose()
		explicit.dispose()
		sideways.dispose()
	end)

	it("itemExtent / viewportExtent are the canonical names and land in the dump", function()
		local core = LuauUI.newCore()
		local rows = core:signal(makeRows(8))
		local list = newList(core, { rows = rows, itemExtent = 56, viewportExtent = 200 })
		local d = list.dump()
		expect(`{d.itemExtent}|{d.viewportExtent}|{d.axis}`).toBe("56|200|y")
		list.dispose()
	end)

	it("rowHeight / viewportHeight still work UNCHANGED — the deprecated aliases (ADR-0011)", function()
		local core = LuauUI.newCore()
		local rows = core:signal(makeRows(8))
		-- the SAME list, spelled both ways: the two dumps must agree field for field
		local canonical = newList(core, { rows = rows, itemExtent = 56, viewportExtent = 200 })
		local legacy = newList(core, { rows = rows, legacyNames = true, itemExtent = 56, viewportExtent = 200 })
		local a, b = canonical.dump(), legacy.dump()
		for key, value in a :: any do
			if key ~= "window" then
				expect(`{key}={tostring((b :: any)[key])}`).toBe(`{key}={tostring(value)}`)
			end
		end
		-- ...and on the DEFAULT axis the deprecated names are still reported, so an
		-- existing reader of `dump().rowHeight` sees the number it always saw
		expect(`{b.rowHeight}|{b.viewportHeight}`).toBe("56|200")
		-- a live Readable works through the alias exactly as through the canonical
		local extent = core:signal(56)
		local live = newList(core, { rows = rows, legacyNames = true, itemExtent = extent, viewportExtent = 200 })
		expect(live.dump().itemExtent).toBe(56)
		extent:set(72)
		expect(`{live.dump().itemExtent}|{live.dump().rowHeight}`).toBe("72|72")
		canonical.dispose()
		legacy.dispose()
		live.dispose()
	end)

	it("the deprecated names are ABSENT from a horizontal dump — a rowHeight there is a lie", function()
		local core = LuauUI.newCore()
		local rows = core:signal(makeRows(8))
		local list = newList(core, { rows = rows, axis = "x", itemExtent = 120, viewportExtent = 400 })
		local d = list.dump()
		expect(d.itemExtent).toBe(120)
		expect(d.viewportExtent).toBe(400)
		expect(d.rowHeight).toBe(nil)
		expect(d.viewportHeight).toBe(nil)
		list.dispose()
	end)

	it("a name and its alias TOGETHER are refused, naming both and which is deprecated", function()
		local core = LuauUI.newCore()
		local rows = core:signal(makeRows(4))
		local function build(extra: any)
			local spec: any = {
				id = "VL",
				rows = rows,
				key = function(item: any)
					return item.id
				end,
				cell = function()
					return LuauUI.UI.Text({ id = "L", text = "x", textSize = 14 })
				end,
			}
			for key, value in extra do
				spec[key] = value
			end
			return virtual_list.build(LuauUI, core, spec)
		end
		local ok, err = pcall(build, { itemExtent = 40, rowHeight = 40, viewportExtent = 200 })
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "itemExtent", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "rowHeight", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "deprecated alias", 1, true) ~= nil).toBe(true)

		local ok2, err2 = pcall(build, { itemExtent = 40, viewportExtent = 200, viewportHeight = 200 })
		expect(ok2).toBe(false)
		expect(string.find(tostring(err2), "viewportExtent", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err2), "viewportHeight", 1, true) ~= nil).toBe(true)
	end)

	it("both deprecations are in LuauUI.DEPRECATIONS with a replacement and a minor of notice", function()
		local wanted = {
			["newVirtualList(spec.rowHeight)"] = "itemExtent",
			["newVirtualList(spec.viewportHeight)"] = "viewportExtent",
		}
		local seen: { [string]: boolean } = {}
		for _, entry in LuauUI.DEPRECATIONS :: { any } do
			local want = wanted[entry.surface]
			if want ~= nil then
				seen[entry.surface] = true
				expect(string.find(entry.replacement, want, 1, true) ~= nil).toBe(true)
			end
		end
		for surface in wanted do
			expect(`{surface} in ledger: {seen[surface] == true}`).toBe(`{surface} in ledger: true`)
		end
	end)

	it('rowActions is refused on axis = "x", and the refusal says WHY (the gesture collides)', function()
		local core = LuauUI.newCore()
		local rows = core:signal(makeRows(4))
		local ok, err = pcall(function()
			virtual_list.build(LuauUI, core, {
				id = "VL",
				rows = rows,
				key = function(item: any)
					return item.id
				end,
				axis = "x",
				itemExtent = 120,
				viewportExtent = 400,
				cell = function()
					return LuauUI.UI.Text({ id = "L", text = "x", textSize = 14 })
				end,
				rowActions = function()
					return { trailing = { { id = "del", label = "Delete", onActivate = function() end } } }
				end,
			})
		end)
		expect(ok).toBe(false)
		local message = tostring(err)
		expect(string.find(message, "rowActions", 1, true) ~= nil).toBe(true)
		-- the REASON, not merely the prohibition: a refusal whose reason is
		-- unstated gets "fixed" by the next agent
		expect(string.find(message, "swipe", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "scroll gesture", 1, true) ~= nil).toBe(true)
		-- ...and the identical spec is perfectly legal on the default axis
		local fine = virtual_list.build(LuauUI, core, {
			id = "VL2",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			itemExtent = 40,
			viewportExtent = 200,
			cell = function()
				return LuauUI.UI.Text({ id = "L", text = "x", textSize = 14 })
			end,
			rowActions = function()
				return { trailing = { { id = "del", label = "Delete", onActivate = function() end } } }
			end,
		})
		expect(fine.dump().axis).toBe("y")
		fine.dispose()
	end)

	it('`width` is refused on axis = "x" — there, the width IS viewportExtent', function()
		local core = LuauUI.newCore()
		local rows = core:signal(makeRows(4))
		local function build(axis: string?)
			return virtual_list.build(LuauUI, core, {
				id = "VL",
				rows = rows,
				key = function(item: any)
					return item.id
				end,
				axis = axis,
				itemExtent = 40,
				viewportExtent = 200,
				width = { type = "fixed", px = 300 },
				cell = function()
					return LuauUI.UI.Text({ id = "L", text = "x", textSize = 14 })
				end,
			})
		end
		local ok, err = pcall(build, "x")
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "viewportExtent", 1, true) ~= nil).toBe(true)
		-- ...and it is untouched on the default axis, where width is the CROSS axis
		local vertical = build(nil)
		expect(vertical.dump().axis).toBe("y")
		vertical.dispose()
	end)
end)

-- ===========================================================================
describe("VirtualList.axis — the windowing arithmetic reads the x canvas", function()
	it("the content extent is N*itemExtent + (N-1)*rowGap along x, with no trailing gutter", function()
		local core = LuauUI.newCore()
		local rows = core:signal(makeRows(8))
		local list = newList(core, {
			rows = rows,
			axis = "x",
			itemExtent = 120,
			rowGap = 6,
			viewportExtent = 400,
		})
		list.bindNativeScroll(scrollStub(), "/VL")
		-- the scroll clamp is the whole truth about the content extent
		list.scrollTop:set(100000)
		expect(list.dump().scrollTop).toBe(8 * 120 + 7 * 6 - 400)
		rows:set(makeRows(1))
		list.scrollTop:set(100000)
		expect(list.dump().scrollTop).toBe(0)
		list.dispose()
	end)

	it("window membership steps on the PITCH along x", function()
		local core = LuauUI.newCore()
		local rows = core:signal(makeRows(200))
		-- 126 pitch, a 252 px viewport = exactly 2 whole slots, no overscan
		local list = newList(core, {
			rows = rows,
			axis = "x",
			itemExtent = 120,
			rowGap = 6,
			viewportExtent = 252,
			overscan = 0,
		})
		expect(list.dump().window).toEqual({ "r1", "r2" })
		list.scrollTop:set(10 * 126)
		expect(list.dump().window).toEqual({ "r11", "r12" })
		list.dispose()
	end)

	it("keep-visible writes the target on X, and leaves Y at zero (the discriminator)", function()
		local core = LuauUI.newCore()
		local rows = core:signal(makeRows(100))
		local list = newList(core, { rows = rows, axis = "x", itemExtent = 120, viewportExtent = 400 })
		local ctrl = scrollStub()
		list.bindNativeScroll(ctrl, "/VL")
		list.focusKey("r20")
		-- item 20 starts at 19*120 and is 120 wide, so the minimal RIGHTWARD scroll
		-- parks its trailing edge on the band's trailing edge
		expect(ctrl.lastPos().x).toBe(19 * 120 + 120 - 400)
		expect(ctrl.lastPos().y).toBe(0)
		list.focusKey("r1")
		expect(ctrl.lastPos().x).toBe(0)
		list.dispose()
	end)

	it("the CanvasPosition mirror reads .X on a horizontal list (and .Y on a vertical one)", function()
		local core = LuauUI.newCore()
		local rows = core:signal(makeRows(100))
		local sideways = newList(core, { rows = rows, axis = "x", itemExtent = 120, viewportExtent = 400 })
		local ctrl = scrollStub()
		sideways.bindNativeScroll(ctrl, "/VL")
		ctrl.scrollTo("/VL", { x = 600, y = 999 })
		expect(sideways.scrollTop:get()).toBe(600)

		local down = newList(core, { rows = rows, itemExtent = 120, viewportExtent = 400 })
		local ctrl2 = scrollStub()
		down.bindNativeScroll(ctrl2, "/VL")
		ctrl2.scrollTo("/VL", { x = 999, y = 600 })
		expect(down.scrollTop:get()).toBe(600)
		sideways.dispose()
		down.dispose()
	end)

	it("scrollTo clamps and writes along the list's own axis", function()
		local core = LuauUI.newCore()
		local rows = core:signal(makeRows(10))
		local list = newList(core, { rows = rows, axis = "x", itemExtent = 120, viewportExtent = 400 })
		local ctrl = scrollStub()
		list.bindNativeScroll(ctrl, "/VL")
		list.scrollTo(ctrl, 100000)
		expect(ctrl.lastPos().x).toBe(10 * 120 - 400)
		expect(ctrl.lastPos().y).toBe(0)
		list.dispose()
	end)
end)

-- ===========================================================================
describe("VirtualList.axis — the presented canvas is a full-WIDTH one", function()
	it("declares an x scroll region whose contentW is the full virtual extent", function()
		local w = world({ axis = "x", count = 100, itemExtent = 120, viewportExtent = 400 })
		local host = w.adapter.node("/S/VL")
		expect(host.props.clipChildren).toBe(true)
		expect(host.scrollRegion.axis).toBe("x")
		expect(host.scrollRegion.contentW).toBe(100 * 120)
		--[[ THE CROSS AXIS DOES NOT ACCUMULATE (A-SV1's own rule). The number
			itself is the MEASURED content height, which arrangement then stretches
			to the host — what matters is that it is not a sum over items. Pinning
			the invariant rather than the number: a list that summed the wrong axis
			would grow this with the count. ]]
		local crossBefore = host.scrollRegion.contentH
		expect(crossBefore < 100 * 120).toBe(true)
		w.rows:set(makeRows(200))
		w.pres.refresh()
		local after = w.adapter.node("/S/VL").scrollRegion
		expect(after.contentW).toBe(200 * 120)
		expect(after.contentH).toBe(crossBefore)
		expect(#w.diagnostics()).toBe(0)
	end)

	it("items sit at absolute canvas X offsets and are itemExtent WIDE, filling the height", function()
		local w = world({ axis = "x", count = 100, itemExtent = 120, viewportExtent = 400 })
		local canvasX = w.adapter.node("/S/VL/Canvas").rect.x
		expect(w.rect("r1").x - canvasX).toBe(0)
		expect(w.rect("r3").x - canvasX).toBe(2 * 120)
		expect(w.rect("r1").w).toBe(120)
		-- the cross axis fills the viewport, so every item is the host's height
		expect(w.rect("r1").h).toBe(w.hostRect().h)
		expect(w.rect("r1").y).toBe(w.hostRect().y)
		expect(#w.diagnostics()).toBe(0)
	end)

	it("rowGap is the gutter ALONG the axis: dead space between items, never inside one", function()
		local w = world({ axis = "x", count = 20, itemExtent = 120, rowGap = 6, viewportExtent = 400 })
		local a, b = w.rect("r1"), w.rect("r2")
		expect(a.w).toBe(120)
		expect(b.x - a.x).toBe(126)
		expect(b.x - (a.x + a.w)).toBe(6)
		-- the gutter is on the SCROLL axis only — the items are not inset vertically
		expect(b.y).toBe(a.y)
		expect(b.h).toBe(a.h)
		expect(#w.diagnostics()).toBe(0)
	end)

	it("the canvas grows sideways with the data", function()
		local w = world({ axis = "x", count = 20, itemExtent = 120, viewportExtent = 400 })
		expect(w.adapter.node("/S/VL").scrollRegion.contentW).toBe(20 * 120)
		w.rows:set(makeRows(50))
		w.pres.refresh()
		expect(w.adapter.node("/S/VL").scrollRegion.contentW).toBe(50 * 120)
		expect(#w.diagnostics()).toBe(0)
	end)

	it("only the window mounts: a 1000-item strip is still a bounded window", function()
		local w = world({ axis = "x", count = 1000, itemExtent = 120, viewportExtent = 480 })
		local mounted = 0
		for _ in w.list.debugWindow() do
			mounted += 1
		end
		-- ceil(480/120) = 4 visible + 2 overscan trailing (the leading edge clamps)
		expect(mounted).toBe(6)
		w.adapter.driveScroll("/S/VL", { x = 120 * 500, y = 0 })
		w.pres.refresh()
		mounted = 0
		for _ in w.list.debugWindow() do
			mounted += 1
		end
		expect(mounted).toBe(8) -- + 2 overscan leading
		expect(#w.diagnostics()).toBe(0)
	end)
end)

-- ===========================================================================
-- FOUR-INPUT PROOF for the new axis (ui_todo §0; ADR-0013). Every case drives a
-- REAL device path — adapter.tap / adapter.driveScroll for pointer & touch,
-- system.deviceKey for keyboard & gamepad — with ZERO consumer present() wiring.
-- ===========================================================================
describe("VirtualList horizontal pointer input (no consumer wiring)", function()
	it("VirtualList pointer: a horizontal engine scroll slides the window along x", function()
		local w = world({ axis = "x", count = 100, itemExtent = 120, viewportExtent = 480 })
		expect(w.list.scrollTop:get()).toBe(0)
		w.adapter.driveScroll("/S/VL", { x = 360, y = 0 })
		expect(w.list.scrollTop:get()).toBe(360)
		w.pres.refresh()
		expect(w.list.debugWindow().r1).toBe(nil)
		expect(w.list.debugWindow().r9).toBe(true)
		-- each mounted item still sits at its ABSOLUTE canvas x (the engine
		-- translates by CanvasPosition; the framework never re-arranges)
		expect(w.adapter.node(w.hitPath("r9")).rect.x - w.adapter.node("/S/VL/Canvas").rect.x).toBe(8 * 120)
		expect(#w.diagnostics()).toBe(0)
	end)

	it("VirtualList pointer: a tap on a horizontal item activates through auto handleActivate", function()
		local w = world({ axis = "x", count = 100, itemExtent = 120, viewportExtent = 480 })
		w.adapter.tap(w.hitPath("r2"))
		expect(#w.activations).toBe(1)
		expect(w.activations[1].item.id).toBe("r2")
	end)
end)

describe("VirtualList horizontal touch input (no consumer wiring)", function()
	it("VirtualList touch: a native sideways pan slides the window and never activates", function()
		local w = world({ axis = "x", count = 100, itemExtent = 120, viewportExtent = 480 })
		w.adapter.driveScroll("/S/VL", { x = 240, y = 0 })
		expect(w.list.scrollTop:get()).toBe(240)
		w.pres.refresh()
		expect(w.list.debugWindow().r7).toBe(true)
		expect(#w.activations).toBe(0)
		-- a garbage/negative mirror value cannot mount a phantom window before the start
		w.adapter.driveScroll("/S/VL", { x = -900, y = 0 })
		expect(w.list.dump().scrollTop).toBe(0)
		expect(w.list.debugWindow().r1).toBe(true)
	end)

	it("VirtualList touch: a tap on a horizontal item activates", function()
		local w = world({ axis = "x", count = 100, itemExtent = 120, viewportExtent = 480 })
		w.adapter.tap(w.hitPath("r3"), { pointer = "touch" })
		expect(#w.activations).toBe(1)
		expect(w.activations[1].item.id).toBe("r3")
	end)
end)

describe("VirtualList horizontal keyboard input (no consumer wiring)", function()
	it("VirtualList keyboard: Left/Right steps a horizontal list item-by-item", function()
		local w = world({ axis = "x", count = 100, itemExtent = 120, viewportExtent = 480 })
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r1"))
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r2"))
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r3"))
		w.system.deviceKey("Left", true)
		w.system.deviceKey("Left", false)
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r2"))
		expect(w.list.focusedKey:get()).toBe("r2")
	end)

	it("VirtualList keyboard: Up/Down do NOT step a horizontal list — ONE map, read one way", function()
		--[[ THE DISCRIMINATOR for "the focus map declares the list's axis". A group
			that still said `vertical` would step on Up/Down here and be dead on
			Left/Right — the exact defect the group-axis line exists to prevent, and
			the reason it is the group's axis rather than a second order. ]]
		local w = world({ axis = "x", count = 100, itemExtent = 120, viewportExtent = 480 })
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r1"))
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r1"))
		w.system.deviceKey("Up", true)
		w.system.deviceKey("Up", false)
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r1"))
	end)

	it("VirtualList keyboard: focus past the horizontal window edge scrolls it into view", function()
		local w = world({ axis = "x", count = 100, itemExtent = 120, viewportExtent = 480 })
		for _ = 1, 6 do
			w.system.deviceKey("Right", true)
			w.system.deviceKey("Right", false)
			w.pres.refresh()
		end
		local key = w.list.focusedKey:get() :: string
		local index = tonumber(string.match(key, "r(%d+)")) :: number
		expect(index).toBe(7)
		local left = w.list.scrollTop:get()
		expect(left > 0).toBe(true)
		-- the focused item is fully inside the band, measured on x
		expect((index - 1) * 120 >= left).toBe(true)
		expect((index - 1) * 120 + 120 <= left + 480).toBe(true)
		expect(#w.diagnostics()).toBe(0)
	end)

	it("VirtualList keyboard: Return activates the focused horizontal item", function()
		local w = world({ axis = "x", count = 100, itemExtent = 120, viewportExtent = 480 })
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		expect(#w.activations).toBe(1)
		expect(w.activations[1].item.id).toBe("r2")
		expect(w.activations[1].meta.source).toBe("action")
	end)
end)

describe("VirtualList horizontal gamepad input (no consumer wiring)", function()
	it("VirtualList gamepad: DPadLeft/DPadRight move focus identically to arrows", function()
		local w = world({ axis = "x", count = 100, itemExtent = 120, viewportExtent = 480 })
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r1"))
		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r2"))
		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r3"))
		w.system.deviceKey("DPadLeft", true)
		w.system.deviceKey("DPadLeft", false)
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r2"))
		-- DPadDown is inert here, exactly as Down is
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r2"))
	end)

	it("VirtualList gamepad: ButtonA activates the focused horizontal item", function()
		local w = world({ axis = "x", count = 100, itemExtent = 120, viewportExtent = 480 })
		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(#w.activations).toBe(1)
		expect(w.activations[1].item.id).toBe("r2")
	end)
end)

-- ===========================================================================
describe("VirtualList.axis — drag, drop line and edge autoscroll follow the axis", function()
	it("the predicted insertion slot is read from the pointer's X", function()
		local w = world({
			axis = "x",
			count = 40,
			itemExtent = 120,
			viewportExtent = 480,
			reorderable = true,
		})
		w.liftX("r1")
		local r4 = w.rect("r4")
		-- just past r4's trailing edge is the boundary between slot 4 and slot 5;
		-- with the dragged r1 removed first, landing there is index 4
		w.moveToX("r1", r4.x + r4.w + 3)
		expect(w.list.dropIndex:get()).toBe(4)
		--[[ ...and the hairline itself was translated ON X. It is parked far
			BEFORE the canvas origin when idle and moved by the presentation
			channel, so the composed offset is the whole evidence: a list that still
			wrote `{x = 0, y = boundary}` would leave the indicator parked off-canvas
			(x still at the park value) while the slot it names moved. ]]
		local line = w.adapter.node("/S/VL/Canvas/DropLine")
		expect(line ~= nil).toBe(true)
		expect(line.presentationOffset.x).toBe(4 * 120)
		expect(line.presentationOffset.y).toBe(0)
		-- the indicator is a THICKNESS on the scroll axis, standing across it
		expect(line.rect.h).toBe(w.hostRect().h)
		expect(line.rect.w < line.rect.h).toBe(true)
	end)

	it("the ARMED cursor steps on Right/Left, and Up/Down are inert (the same axis focus walks)", function()
		--[[ `navigateIntercept` is the ONE flow that moves a cursor without moving
			focus, so it carries its own copy of "which two directions step". If it
			kept the vertical pair while the focus group went horizontal, a pad user
			would arm a row and then find the predicted slot moving on a direction
			the ring does not walk — two orders for one list, which is exactly what
			constitution §9 forbids. ]]
		local w = world({
			axis = "x",
			count = 40,
			itemExtent = 120,
			viewportExtent = 480,
			reorderable = true,
		})
		w.list.focusKey("r1")
		expect(w.list.toggleGrab()).toBe(true)
		expect(w.list.armedKey:get()).toBe("r1")
		-- the ORTHOGONAL pair is consumed and moves nothing: the predicted slot is
		-- still the armed row's own, exactly as it was before the press
		local armedAt = w.list.dropIndex:get()
		expect(armedAt).toBe(1)
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.list.dropIndex:get()).toBe(armedAt)
		for _ = 1, 3 do
			w.system.deviceKey("DPadRight", true)
			w.system.deviceKey("DPadRight", false)
			w.pres.refresh()
		end
		expect(w.list.dropIndex:get()).toBe(4)
		w.list.toggleGrab() -- commit
		expect(w.reorders[1]).toEqual({ key = "r1", toIndex = 4 })
	end)

	it("the COMMITTED index is read from the release point's X, not its Y", function()
		--[[ The predicted slot (above) and the committed index travel different
			code paths — the registry's live `onUpdate` state versus its terminal
			`info` — so each needs its own discriminator. On a horizontal list every
			row shares the same y, so a commit that still read `info.pointerY` would
			resolve to slot 0 for every drop and land r1 back where it started. ]]
		local w = world({
			axis = "x",
			count = 40,
			itemExtent = 120,
			viewportExtent = 480,
			reorderable = true,
		})
		w.liftX("r1")
		local r4 = w.rect("r4")
		local drop = r4.x + r4.w - 5 -- the trailing half of item 4
		w.moveToX("r1", drop)
		w.releaseX("r1", drop)
		expect(#w.reorders).toBe(1)
		expect(w.reorders[1].key).toBe("r1")
		expect(w.reorders[1].toIndex).toBe(4)
	end)

	it("edge autoscroll drives X and reports LEFT/RIGHT bands, never top/bottom", function()
		local w = world({
			axis = "x",
			count = 40,
			itemExtent = 120,
			viewportExtent = 480,
			reorderable = true,
		})
		local host = w.hostRect()
		w.liftX("r1")
		w.moveToX("r1", host.x + host.w - 5) -- deep in the trailing band
		expect(w.list.stepAutoscroll(0).delta).toBe(0)
		expect(w.list.stepAutoscroll(0.2).delta).toBe(0) -- the dwell has not paid
		expect(w.list.scrollTop:get()).toBe(0)
		local armed = w.list.stepAutoscroll(0.35)
		expect(armed.state).toBe("active")
		expect(w.list.autoscroll:get().band).toBe("right")
		local before = w.list.scrollTop:get()
		w.list.stepAutoscroll(0.6)
		expect(w.list.scrollTop:get() > before).toBe(true)
		-- ...and the leading band answers "left"
		w.moveToX("r1", host.x + 3)
		w.list.stepAutoscroll(1.0)
		w.list.stepAutoscroll(1.4)
		expect(w.list.autoscroll:get().band).toBe("left")
	end)

	it("a VERTICAL list still reports top/bottom — the band names are not globally renamed", function()
		local w = world({ count = 40, itemExtent = 40, viewportExtent = 400, reorderable = true })
		local host = w.hostRect()
		local r1 = w.rect("r1")
		w.adapter.driveDragStart(w.hitPath("r1"), { x = 100, y = r1.y + r1.h / 2, pointerType = "mouse" })
		w.adapter.driveDragContinue(
			w.hitPath("r1"),
			{ x = 100, y = host.y + host.h - 5, pointerType = "mouse" },
			{ x = 0, y = 0 }
		)
		w.list.stepAutoscroll(0)
		w.list.stepAutoscroll(0.35)
		expect(w.list.autoscroll:get().band).toBe("bottom")
	end)
end)

-- ===========================================================================
-- THE NEUTRALITY PIN. Everything above adds a branch; this is the case that says
-- the branch is never taken by a list that declares no axis. It is deliberately
-- redundant with the vertical suite: those cases would also catch a regression,
-- but this one names the reason, so a future axis change knows what it broke.
describe("VirtualList.axis — a list declaring no axis builds what it always did", function()
	it("vertical remains the default end to end: region, offsets, focus order, keep-visible", function()
		local w = world({ count = 100, itemExtent = 40, viewportExtent = 400 })
		local host = w.adapter.node("/S/VL")
		expect(host.scrollRegion.axis).toBe("y")
		expect(host.scrollRegion.contentH).toBe(100 * 40)
		local canvasY = w.adapter.node("/S/VL/Canvas").rect.y
		expect(w.rect("r1").y - canvasY).toBe(0)
		expect(w.rect("r3").y - canvasY).toBe(2 * 40)
		-- ...and the focus group is still vertical: Down steps, Right does not
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r1"))
		w.system.deviceKey("Down", true)
		w.system.deviceKey("Down", false)
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r2"))
		w.system.deviceKey("Right", true)
		w.system.deviceKey("Right", false)
		expect(w.pres.focus.focused:get()).toBe(w.hitPath("r2"))
		-- ...and keep-visible still writes Y
		w.adapter.takeOps()
		for _ = 1, 12 do
			w.system.deviceKey("Down", true)
			w.system.deviceKey("Down", false)
			w.pres.refresh()
		end
		expect(w.adapter.node("/S/VL").scrollPosition.y > 0).toBe(true)
		expect(w.adapter.node("/S/VL").scrollPosition.x).toBe(0)
		expect(#w.diagnostics()).toBe(0)
	end)

	it("the DEPRECATED spelling builds the identical vertical geometry", function()
		local canonical = world({ count = 40, itemExtent = 56, viewportExtent = 200 })
		local legacy = world({ count = 40, legacyNames = true, itemExtent = 56, viewportExtent = 200 })
		for _, key in { "r1", "r2", "r3" } do
			local a, b = canonical.rect(key), legacy.rect(key)
			expect(`{b.x},{b.y},{b.w},{b.h}`).toBe(`{a.x},{a.y},{a.w},{a.h}`)
		end
		expect(legacy.adapter.node("/S/VL").scrollRegion.axis).toBe("y")
		expect(legacy.adapter.node("/S/VL").scrollRegion.contentH).toBe(40 * 56)
		expect(#legacy.diagnostics()).toBe(0)
	end)
end)
