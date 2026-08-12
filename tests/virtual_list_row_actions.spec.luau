--!strict
-- VirtualList HOSTED ROW ACTIONS (row-actions perf mission, Task 3 —
-- docs/plans/row-actions-hosted-mode-design.md §"Hosted mode: a closed row
-- mounts NOTHING"). `newVirtualList.rowActions` wires ONE shared four-function
-- pointer dispatcher onto every row's EXISTING `Hit` Button and builds the
-- per-row gesture engine (`row_actions.buildHosted`, Task 2) LAZILY — on the
-- first pointer-down that lands on that row, never while scrolling.
--
-- WHAT THIS FILE IS THE NET FOR:
--   * laziness — a mounted, scrolled, untouched list holds ZERO engines;
--   * first-gesture creation — exactly one engine, for exactly the row touched;
--   * the v1 refusal — `rowActions` + `reorderable` on one list;
--   * MOUNT IDENTITY — a `rowActions` list's mounted path set is identical to a
--     plain list's (Task 3 adds no node at all; the tray overlay is Task 4), and
--     the only difference in the row subtree is the four handler props on `Hit`;
--   * scroll-close — the shared coordinator closes the engaged row on any scroll.
--
-- Pointer input goes through the REAL device seam
-- (`adapter.pointerDown/pointerMove/pointerUp` against the mounted `Hit` path),
-- the same idiom tests/row_actions_input.spec.luau's own `pointerWorld` uses,
-- with a SCRIPTED `now` so the springs and the gesture's velocity tracker are
-- deterministic.
--
-- WHAT IS DELIBERATELY NOT HERE YET (Task 4 owns it): the shared tray overlay.
-- Without a mounted tray, `trailingWidth` never measures, so `targetFor(edge)`
-- is 0 and a released gesture settles back to 0 px — an "open at the tray
-- width" assertion cannot exist until the overlay does. Every engagement
-- assertion below is therefore made on a LIVE (held) gesture, which is the real
-- state the shared signals and the coordinator claim are driven from anyway.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local row_actions_state = require("../src/input/row_actions_state")
local fake_target = require("../tests/lib/fake_target")

local LOCK = row_actions_state.AXIS_LOCK_PX
local FRAME = 1 / 60

local function makeRows(n: number): { { id: string, label: string } }
	local rows = {}
	for i = 1, n do
		table.insert(rows, { id = `r{i}`, label = `Row {i}` })
	end
	return rows
end

-- the mounted row-hit path — the node the shared dispatcher is wired onto
local function rowHit(key: string): string
	return `/S/VL/Canvas/W/[{key}]/Row/Hit`
end

--[[ A presented VirtualList with a scripted clock. `opts.rowActions` is handed
	straight to the spec (omit for a PLAIN list — the mount-identity control);
	`opts.reorderable` exists only for the v1-refusal case. `w.tick(dt)` is one
	host frame: advance the scripted `now`, step the presenter's motion clock,
	and run the full sync pass (`pres.refresh()` is what feeds every
	contribution's `syncGeometry`, which is how a hosted engine measures). ]]
local function world(opts: any?): any
	local options = opts or {}
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local clockTime = 0
	local pres = LuauUI.newPresenter(core, env, adapter, system, {
		now = function()
			return clockTime
		end,
	})
	local rows = core:signal(makeRows(options.count or 100))
	local activations: { string } = {}
	local spec: any = {
		id = "VL",
		rows = rows,
		key = function(item: any)
			return item.id
		end,
		rowHeight = 40,
		viewportHeight = 400, -- 10 visible rows
		overscan = 2,
		cell = function(item: any)
			return LuauUI.UI.Text({ id = "Label", text = item.label, textSize = 14 })
		end,
		onActivate = function(item: any)
			table.insert(activations, item.id)
		end,
	}
	if options.rowActions ~= nil then
		spec.rowActions = options.rowActions
	end
	if options.reorderable ~= nil then
		spec.reorderable = options.reorderable
	end
	if options.dropSurface ~= nil then
		spec.dropSurface = options.dropSurface
	end
	if options.rowDropTarget ~= nil then
		spec.rowDropTarget = options.rowDropTarget
	end
	local list = virtual_list.build(LuauUI, core, spec)
	local screen = LuauUI.UI.Screen({ id = "S", children = { list.blueprint } })
	local handle = pres.present(screen)
	pres.refresh()
	local unbindScroll = list.bindNativeScroll(handle.controller)

	local w: any = {
		core = core,
		adapter = adapter,
		pres = pres,
		list = list,
		rows = rows,
		handle = handle,
		unbindScroll = unbindScroll,
		activations = activations,
		blueprint = list.blueprint,
	}
	function w.tick(dt: number)
		clockTime += dt
		pres.tick(dt)
		pres.refresh()
	end
	function w.settle(frames: number?)
		for _ = 1, frames or 90 do
			w.tick(FRAME)
		end
	end
	function w.debug(): any
		return list._hostedDebug()
	end
	-- a horizontal swipe on `key`'s hit, LEFT by `dx` past the axis lock, held
	-- (no release) — see the header for why the assertions live on a held drag
	local lastPos = { x = 0, y = 0 }
	-- `originInset` moves the press's starting x left of the row's right edge. It
	-- exists so a second gesture on the SAME row can start somewhere the first
	-- one did not: a dispatcher that lost a gesture's end leaves the engine's own
	-- `drag.originX` at the PREVIOUS origin, and measuring the same finger
	-- positions against it yields a different offset — which is the only thing
	-- that tells the two states apart from the outside.
	function w.dragLeft(key: string, dx: number, pointerType: string?, originInset: number?)
		local hit = rowHit(key)
		local rect = adapter.node(hit).rect
		local originX = rect.x + rect.w - (originInset or 20)
		local y = rect.y + rect.h / 2
		adapter.pointerDown(hit, originX, y, pointerType or "mouse")
		w.tick(FRAME)
		adapter.pointerMove(originX - (LOCK + 2), y) -- crosses the lock, horizontal
		w.tick(FRAME)
		adapter.pointerMove(originX - dx, y)
		w.tick(FRAME)
		lastPos = { x = originX - dx, y = y }
	end
	-- a VERTICAL pan/fling that happens to begin on a row — what a phone user
	-- does to scroll, and the case the deferred build exists for
	function w.dragDown(key: string, dy: number, pointerType: string?)
		local hit = rowHit(key)
		local rect = adapter.node(hit).rect
		local x = rect.x + rect.w / 2
		local originY = rect.y + rect.h / 2
		adapter.pointerDown(hit, x, originY, pointerType or "touch")
		w.tick(FRAME)
		adapter.pointerMove(x, originY + LOCK + 2)
		w.tick(FRAME)
		adapter.pointerMove(x, originY + dy)
		w.tick(FRAME)
		lastPos = { x = x, y = originY + dy }
	end
	-- release WHERE THE FINGER IS. Releasing at some arbitrary point (0,0, say)
	-- hands the gesture's velocity tracker a jump of hundreds of px in one frame
	-- — a flick nothing physical could produce, which settles the row somewhere
	-- the test never asked for.
	function w.release()
		adapter.pointerUp(lastPos.x, lastPos.y)
		w.tick(FRAME)
	end
	-- a FULL SWIPE: past 60% of the row, released. The only gesture whose
	-- verdict depends on a LIVE row rect, which is why it is the differential
	-- the stale-path case (I2) is proven with.
	function w.swipeCommit(key: string)
		local hit = rowHit(key)
		local rect = adapter.node(hit).rect
		w.dragLeft(key, rect.w * 0.75)
		w.release()
		w.settle()
	end
	return w
end

-- one trailing "Delete" per row; `fired` records every invocation
local function trailingActions(fired: { string }): (item: any) -> any
	return function(item: any): any
		return {
			trailing = {
				{
					id = "delete",
					label = "Delete",
					onAction = function()
						table.insert(fired, item.id)
					end,
				},
			},
		}
	end
end

-- =============================================================================
describe("VirtualList rowActions (Task 3): lazy hosted engines", function()
	it("(a) a mounted, scrolled, untouched list holds ZERO engines", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		expect(w.debug().engineCount).toBe(0)
		expect(w.debug().engagedKey).toBeNil()
		-- STEADY SCROLLING is the case laziness exists for: every one of these
		-- slides the window (rows mount and unmount) and not one of them may
		-- construct a gesture engine.
		for y = 40, 800, 40 do
			w.adapter.driveScroll("/S/VL", { x = 0, y = y })
			w.pres.refresh()
		end
		expect(w.list.scrollTop:get()).toBe(800)
		expect(w.debug().engineCount).toBe(0)
		expect(w.debug().engagedKey).toBeNil()
	end)

	it("(b) the first horizontal gesture on a row builds exactly ONE engine and engages that row", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		expect(w.debug().engineCount).toBe(1)
		expect(w.debug().engagedKey).toBe("r2")
		expect(w.list.engagedOffset:get()).toBe(-80)
		-- ...and a second gesture on the SAME row reuses it (the cache is real)
		w.release()
		w.settle(20)
		w.dragLeft("r2", 60)
		expect(w.debug().engineCount).toBe(1)
	end)

	it("(b2) a gesture on a SECOND row builds a second engine; the first row is closed by the coordinator", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		expect(w.debug().engagedKey).toBe("r2")
		w.release()
		w.dragLeft("r4", 80)
		expect(w.debug().engineCount).toBe(2)
		expect(w.debug().engagedKey).toBe("r4")
	end)

	it("(b3) a VERTICAL drag builds NO engine at all and never engages", function()
		-- THE TOUCH LAZINESS CASE. A phone user pans and flings THROUGH rows all
		-- day, and every one of those gestures begins with a pointer-down on a
		-- row. Building at the down would have made "lazy" mean "lazy until the
		-- player scrolls once" — so the build waits for the axis lock, and a
		-- gesture that resolves vertical never reaches it.
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragDown("r2", 120)
		expect(w.debug().engineCount).toBe(0)
		expect(w.debug().engagedKey).toBeNil()
		expect(w.list.engagedOffset:get()).toBe(0)
		w.release()
		expect(w.debug().engineCount).toBe(0)
	end)

	it("(b3b) a touch FLING across many rows builds zero engines", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		-- five separate flings, each starting on a different row, with the engine
		-- scroll mirroring in between — the steady-state phone gesture
		for i, key in { "r1", "r3", "r5", "r7", "r9" } do
			w.dragDown(key, 200, "touch")
			w.release()
			w.adapter.driveScroll("/S/VL", { x = 0, y = i * 60 })
			w.pres.refresh()
		end
		expect(w.debug().engineCount).toBe(0)
		expect(w.debug().engagedKey).toBeNil()
	end)

	it("(b4) a row whose rowActions() returns nil never builds an engine and declines the capture", function()
		local w = world({
			rowActions = function(item: any): any
				if item.id ~= "r3" then
					return nil -- unwrapped row
				end
				return { trailing = { { id = "x", label = "X", onAction = function() end } } }
			end,
		})
		w.dragLeft("r2", 80)
		expect(w.debug().engineCount).toBe(0)
		expect(w.debug().engagedKey).toBeNil()
		-- THE DECLINE IS LOAD-BEARING, and this is what proves it: no pointerUp
		-- happens in between. One live capture owns the pointer (the adapter
		-- mirrors the engine's ADR-0008 capture model), so had the unwrapped row
		-- accepted, the press below would never be delivered to r3 at all.
		w.dragLeft("r3", 80)
		expect(w.debug().engineCount).toBe(1)
		expect(w.debug().engagedKey).toBe("r3")
	end)

	it("(b5) a plain TAP activates the row, builds NO engine, and never engages", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		-- `touchTap`, not `tap`: a real finger is InputBegan -> InputEnded -> then
		-- Activated, and only the three-step driver can see whether the press half
		-- of a tap builds anything (fake_target's own note on why `tap` alone is
		-- not a finger)
		w.adapter.touchTap(rowHit("r1"))
		expect(w.activations).toEqual({ "r1" })
		expect(#fired).toBe(0)
		-- a tap never crosses the axis lock, so the deferred build never runs:
		-- a tap-heavy hosted list accumulates nothing
		expect(w.debug().engineCount).toBe(0)
		expect(w.debug().engagedKey).toBeNil()
		expect(w.list.engagedOffset:get()).toBe(0)
		-- and a plain list is unchanged
		local plain = world()
		plain.adapter.touchTap(rowHit("r1"))
		expect(plain.activations).toEqual({ "r1" })
	end)

	it("(c) rowActions + reorderable is refused at build (v1)", function()
		local core = LuauUI.newCore()
		local ok, err = pcall(function()
			virtual_list.build(LuauUI, core, {
				id = "VL",
				rows = core:signal(makeRows(4)),
				key = function(item: any)
					return item.id
				end,
				rowHeight = 40,
				viewportHeight = 200,
				cell = function(item: any)
					return LuauUI.UI.Text({ id = "L", text = item.label })
				end,
				reorderable = true,
				onReorder = function() end,
				rowActions = function(): any
					return { trailing = { { id = "d", label = "D", onAction = function() end } } }
				end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "rowActions + reorderable is unsupported (v1)", 1, true) ~= nil).toBe(true)
	end)

	it("(d) MOUNT IDENTITY: a rowActions list's mounted paths are identical to a plain list's", function()
		local plain = world()
		local fired: { string } = {}
		local hosted = world({ rowActions = trailingActions(fired) })
		local function pathSet(w: any): { [string]: boolean }
			local set: { [string]: boolean } = {}
			for _, path in w.adapter.paths() do
				set[path] = true
			end
			return set
		end
		local a, b = pathSet(plain), pathSet(hosted)
		for path in a do
			expect(b[path]).toBe(true)
		end
		for path in b do
			expect(a[path]).toBe(true)
		end
		-- ...and every shared node is the same CLASS at the same solved rect
		for path in a do
			local pn, hn = plain.adapter.node(path), hosted.adapter.node(path)
			expect(hn.class).toBe(pn.class)
			if pn.rect ~= nil then
				expect(hn.rect).never().toBeNil()
				expect(hn.rect.x).toBe(pn.rect.x)
				expect(hn.rect.y).toBe(pn.rect.y)
				expect(hn.rect.w).toBe(pn.rect.w)
				expect(hn.rect.h).toBe(pn.rect.h)
			end
		end
		-- the ONE difference is the four handler props on the row Hit: the plain
		-- list's Hit is not even a pointer surface (`node.pointer` is nil), the
		-- hosted one is
		expect(plain.adapter.node(rowHit("r1")).pointer).toBeNil()
		expect(hosted.adapter.node(rowHit("r1")).pointer).never().toBeNil()
	end)

	it("(d2) engaging and disengaging a row returns the mounted tree to the closed shape", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		local before = #w.adapter.paths()
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		expect(#w.adapter.paths()).toBe(before)
		expect(w.debug().engagedKey).toBeNil()
	end)

	it("(e) a scroll closes the engaged row (the shared coordinator's bindScroll)", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		expect(w.debug().engagedKey).toBe("r2")
		-- ANY scroll movement closes the open row (row_actions.newCoordinator's
		-- own bindScroll rule, iOS parity) — driven here through the engine
		-- CanvasPosition mirror, exactly as a finger fling would
		w.adapter.driveScroll("/S/VL", { x = 0, y = 25 })
		w.settle()
		expect(w.debug().engagedKey).toBeNil()
		expect(w.list.engagedOffset:get()).toBe(0)
	end)

	it("(f) a plain list exposes the same debug shape with nothing hosted", function()
		local w = world()
		expect(w.debug().engineCount).toBe(0)
		expect(w.debug().engagedKey).toBeNil()
		-- and the plain row Hit is byte-identical to today: no handler props
		expect(w.adapter.node(rowHit("r1")).pointer).toBeNil()
	end)

	--[[ (h)/(i) THE ROW UNMOUNTED UNDER THE FINGER. The adapter's own
		remove-then-cancel arrives AFTER the row is gone from the window, so a
		dispatcher that re-derived the key from the hit PATH would answer nil at
		exactly that moment: the engine would never be told its gesture ended, its
		internal `drag` would stay live forever, and the "a non-active row may not
		claim" rule would then refuse that row every future press. Both repros
		below were red before the live gesture started routing by held key. ]]
	it("(h) a row scrolled out from under a held finger still works on the next swipe", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		expect(w.debug().engagedKey).toBe("r2")
		-- scroll r2 clean out of the window WHILE THE FINGER IS DOWN
		w.adapter.driveScroll("/S/VL", { x = 0, y = 2000 })
		w.pres.refresh()
		expect(w.list.debugWindow().r2).toBeNil()
		w.release() -- the cancel/up must still land on r2's engine
		w.settle()
		expect(w.debug().engagedKey).toBeNil()
		expect(w.list.engagedOffset:get()).toBe(0)
		-- back to the top, and the SAME row must swipe again — from a DIFFERENT
		-- origin, so a stale `drag` left over from the first gesture would show
		-- up as an offset measured against the wrong starting point
		w.adapter.driveScroll("/S/VL", { x = 0, y = 0 })
		w.pres.refresh()
		w.dragLeft("r2", 80, "mouse", 100)
		expect(w.debug().engagedKey).toBe("r2")
		expect(w.list.engagedOffset:get()).toBe(-80)
	end)

	it("(i) a row REMOVED from the data mid-drag releases the engagement", function()
		local fired: { string } = {}
		local w = world({ count = 6, rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		expect(w.debug().engagedKey).toBe("r2")
		expect(w.debug().engineCount).toBe(1)
		-- the row is deleted out from under the live gesture
		w.rows:set({ { id = "r1" }, { id = "r3" }, { id = "r4" }, { id = "r5" }, { id = "r6" } })
		w.pres.refresh()
		expect(w.debug().engagedKey).toBeNil()
		expect(w.list.engagedOffset:get()).toBe(0)
		-- ...and the dead row's engine went with it, rather than lingering
		expect(w.debug().engineCount).toBe(0)
		w.release()
		w.settle()
		expect(w.debug().engagedKey).toBeNil()
		-- a surviving row still swipes normally afterwards
		w.dragLeft("r4", 80)
		expect(w.debug().engagedKey).toBe("r4")
	end)

	it("(j) a RE-PRESENT drops engines built against the previous mount", function()
		--[[ A hosted engine captures its row path and tray paths at BUILD (it owns
			no nodes, so it can only be told where to look). After a dismiss and a
			re-present under a different root those strings name a tree that is
			gone: `rectOf` answers nil, `rowWidth` is 0, and row_actions_state
			refuses a commit outright at `rowWidth <= 0`. So the differential is a
			FULL SWIPE — the one verdict that needs a live row rect. ]]
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.swipeCommit("r2")
		expect(fired).toEqual({ "r2" }) -- baseline: it commits under /S
		expect(w.debug().engineCount).toBe(1)

		w.pres.dismiss(w.handle)
		local screen2 = LuauUI.UI.Screen({ id = "S2", children = { w.blueprint } })
		local handle2 = w.pres.present(screen2)
		w.pres.refresh()
		w.list.bindNativeScroll(handle2.controller)
		-- the stale engine is gone; the next gesture builds a fresh one
		expect(w.debug().engineCount).toBe(0)

		local hit2 = "/S2/VL/Canvas/W/[r2]/Row/Hit"
		local rect = w.adapter.node(hit2).rect
		local originX = rect.x + rect.w - 20
		local y = rect.y + rect.h / 2
		w.adapter.pointerDown(hit2, originX, y, "mouse")
		w.tick(FRAME)
		w.adapter.pointerMove(originX - (LOCK + 2), y)
		w.tick(FRAME)
		w.adapter.pointerMove(originX - rect.w * 0.75, y)
		w.tick(FRAME)
		w.adapter.pointerUp(originX - rect.w * 0.75, y)
		w.settle()
		expect(fired).toEqual({ "r2", "r2" }) -- committed again, under the new mount
		expect(w.debug().engineCount).toBe(1)
	end)

	it("(k) rowActions COEXISTS with dropSurface: the row is both a swipe hit and a drop target", function()
		local fired: { string } = {}
		local dropped: { string } = {}
		local w = world({
			rowActions = trailingActions(fired),
			dropSurface = true,
			rowDropTarget = function(item: any): any
				return {
					accepts = function(): (boolean, string?)
						return true
					end,
					onDrop = function()
						table.insert(dropped, item.id)
					end,
				}
			end,
		})
		-- `UI.dropTarget` wraps the Hit but declares no drag SOURCE, so the
		-- renderer still wires the node's own pointer props (it only takes the
		-- capture over for a draggable) — the two decls ride the same node
		local hit = w.adapter.node(rowHit("r2"))
		expect(hit.pointer).never().toBeNil()
		w.dragLeft("r2", 80)
		expect(w.debug().engagedKey).toBe("r2")
		expect(w.debug().engineCount).toBe(1)
		w.release()
		w.settle()
		-- ...and the drop declaration is still on the row, unshadowed
		expect(w.list.dump().dropSurface).toBe(true)
	end)

	it("(g) engines survive their row leaving the window, and dispose with the list", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		expect(w.debug().engineCount).toBe(1)
		-- scroll r2 far out of the window: the engine is KEPT (the row comes
		-- back; the scroll already closed it) — see the row-factory comment
		w.adapter.driveScroll("/S/VL", { x = 0, y = 2000 })
		w.pres.refresh()
		expect(w.list.debugWindow().r2).toBeNil()
		expect(w.debug().engineCount).toBe(1)
		w.list.dispose()
		expect(w.debug().engineCount).toBe(0)
	end)
end)
