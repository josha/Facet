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
-- TASK 4 ADDS the second half, in its own describe block at the bottom: the ONE
-- shared tray overlay (a keyed region over the at-most-one engaged row), the
-- presentation-channel slide, the commit-height collapse, and outside-dismiss.
-- Task 3's own cases still assert engagement on a LIVE (held) gesture where
-- that is the state under test — but a RELEASED gesture now settles at the real
-- MEASURED tray width, because the tray it measures finally exists.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local virtual_list = require("../src/controls/virtual_list")
local row_actions_state = require("../src/input/row_actions_state")
local text_metrics = require("../src/layout/text_metrics")
local themeSnapshot = require("../src/themes/snapshot")
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
local function rowPath(key: string): string
	return `/S/VL/Canvas/W/[{key}]/Row`
end

-- ===== the Task 4 overlay's own paths (the contract in virtual_list.luau's
-- header): a KEYED region over the at-most-one engaged row, holding the engine's
-- own tray `When`s — so the tail below is row_actions' shape, unchanged.
local function trayGroup(key: string): string
	return `/S/VL/Canvas/RowActionsOverlay/[{key}]/RowActionsTray`
end
local function tray(key: string, edge: string): string
	local id = if edge == "leading" then "TrayLeading" else "TrayTrailing"
	return `{trayGroup(key)}/{id}When/then/{id}`
end
local function trayAction(key: string, edge: string, action: string): string
	return `{tray(key, edge)}/Action:{action}`
end

--[[ THE TRAY WIDTH A ROW MUST SETTLE OPEN AT, derived independently of this
	control: the framework's own measurement oracle (`text_metrics.measure`,
	unconstrained) over the label at the font/size THE RENDERER published for that
	button (`controller.textAt` — the same fact the engine reads, taken from the
	live tree rather than guessed here), padded and floored by the given theme's
	own `controls.rowActions` metrics. The same shape
	tests/row_actions_hosted.spec.luau's own `expectedTrayWidth` uses, with the
	real renderer standing in for that file's stub controller. ]]
local function expectedTrayWidth(w: any, path: string, label: string, metrics: any?): number
	local snap = metrics or themeSnapshot.neutral()
	local pad = themeSnapshot.resolveNumber(snap, "controls.rowActions.buttonPad") or 0
	local minWidth = themeSnapshot.resolveNumber(snap, "controls.rowActions.buttonMinWidth") or 0
	local facts = w.handle.controller.textAt(path)
	expect(facts).never().toBeNil()
	return math.max(minWidth, text_metrics.measure(label, facts.font, facts.size, math.huge).width + 2 * pad)
end

-- a metrics snapshot with ONE control family retuned — a theme package's whole
-- effect on a tray, without authoring a whole compliant package. Cloned down to
-- the one table that moves; everything else stays the neutral snapshot by
-- reference, so nothing else in the tree solves differently.
local function retunedRowActions(buttonPad: number, buttonMinWidth: number): any
	local base = themeSnapshot.neutral()
	local controls: any = table.clone(base.controls)
	local family: any = table.clone(controls.rowActions)
	family.buttonPad = buttonPad
	family.buttonMinWidth = buttonMinWidth
	controls.rowActions = family
	local snap: any = table.clone(base)
	snap.controls = controls
	return snap
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
		-- the live theme metrics the tray's natural width is measured against.
		-- Passed on every list here (a plain list simply never reads it) so the
		-- hosted/plain mount-identity control stays a control.
		env = env,
	}
	-- a LIVE viewport height (this control accepts a Readable), for the one case
	-- that needs the window to change without a scroll
	local viewportHeight = if options.liveViewport ~= nil then core:signal(options.liveViewport) else nil
	if viewportHeight ~= nil then
		spec.viewportHeight = viewportHeight
	end
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
	local children: { any } = { list.blueprint }
	if options.sibling then
		-- a rendered node OUTSIDE the list, for the outside-tap half of dismiss
		table.insert(
			children,
			LuauUI.UI.Button({
				id = "Outside",
				label = "Outside",
				onActivate = function()
					table.insert(activations, "outside")
				end,
			})
		)
	end
	local screen = LuauUI.UI.Screen({ id = "S", children = children })
	local handle = pres.present(screen)
	pres.refresh()
	local unbindScroll = list.bindNativeScroll(handle.controller)

	local w: any = {
		core = core,
		env = env,
		viewportHeight = viewportHeight,
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
	-- CLOSE THE OPEN ROW the way Task 3 already proves works — a scroll, through
	-- the shared coordinator (case (e)) — so a tree-shape assertion never rests
	-- on Task 4's own tap-to-close. One pixel: not enough to move the window, so
	-- the mounted path SET is untouched by the scroll itself.
	function w.close()
		w.adapter.driveScroll("/S/VL", { x = 0, y = 1 })
		w.pres.refresh()
		w.settle()
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
		--[[ ...and the hosted list adds EXACTLY ONE node: the closed tray overlay
			(design §"What must be proven before ship" — "identical to an unwrapped
			list except the one overlay node"). It is a structural region with no
			branch mounted, i.e. one Frame for the whole LIST, amortized over the
			window at ~0.08 nodes/row — not one per row, which is the entire point
			of hosting the feature instead of wrapping every row in a composite. ]]
		local extra: { string } = {}
		for path in b do
			if a[path] == nil then
				table.insert(extra, path)
			end
		end
		expect(extra).toEqual({ "/S/VL/Canvas/RowActionsOverlay" })
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
		-- OPEN, and the tree says so (Task 4: a released gesture now settles at
		-- the measured tray width instead of snapping back to 0 for want of a
		-- tray to measure)
		expect(w.debug().engagedKey).toBe("r2")
		expect(#w.adapter.paths() > before).toBe(true)
		-- ...and closing it returns the tree to exactly the closed shape
		w.close()
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

	--[[ (l) D1 — THE DOUBLE DELETE. A destructive full swipe fires, and the
		commit chain then springs the row home from its parked slide-off position
		(measured: exactly -800 on this 800px row, for ~65 frames AFTER the action
		fired and `committed` was already cleared). A press landing in that window
		used to be accepted with `drag.startOffset` = -800, so the very next
		release handed `settle()` a magnitude past the 60% commit threshold and
		the row committed a SECOND time. Fixed in the shared engine
		(`commitLatched`, src/controls/row_actions.luau) — see the standalone
		mirror of this case in tests/row_actions_input.spec.luau. ]]
	it("(l) a destructive full swipe fires exactly ONCE, even if re-swiped during the commit", function()
		local fired: { string } = {}
		local w = world({
			rowActions = function(item: any): any
				return {
					trailing = {
						{
							id = "delete",
							label = "Delete",
							role = "destructive",
							onAction = function()
								table.insert(fired, item.id)
							end,
						},
					},
				}
			end,
		})
		local hit = rowHit("r2")
		local rect = w.adapter.node(hit).rect
		local originX = rect.x + rect.w - 20
		local y = rect.y + rect.h / 2
		w.dragLeft("r2", rect.w * 0.75) -- past 60% of the row
		w.release()
		-- run only as far as the FIRE — a destructive commit slides off, collapses
		-- its height, and only then fires; the row is still a whole row width from
		-- home at that moment, and `committed` has just been cleared
		local firedAt: number? = nil
		for i = 1, 400 do
			w.tick(FRAME)
			if #fired == 1 then
				firedAt = i
				break
			end
		end
		expect(firedAt).never().toBeNil()
		expect(w.list.engagedOffset:get()).toBeLessThan(-rect.w * 0.5) -- parked, mid-flight
		-- ...and swipe it again, right here — the whole repro
		w.adapter.pointerDown(hit, originX, y, "mouse")
		w.tick(FRAME)
		w.adapter.pointerMove(originX - (LOCK + 2), y)
		w.tick(FRAME)
		w.adapter.pointerMove(originX - 40, y) -- a SHORT drag: nowhere near 60%
		w.tick(FRAME)
		w.adapter.pointerUp(originX - 40, y)
		-- run the WHOLE ladder out: a second commit would slide off and then
		-- collapse before firing, so a short settle would miss it and pass
		w.settle(400)
		expect(fired).toEqual({ "r2" }) -- still exactly one
	end)

	it("(m) N1: a row that GAINS actions when its item changes stops being declined", function()
		local fired: { string } = {}
		local w = world({
			count = 6,
			rowActions = function(item: any): any
				if item.locked then
					return nil -- no actions while locked
				end
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
			end,
		})
		w.rows:set({ { id = "r1" }, { id = "r2", locked = true }, { id = "r3" } })
		w.pres.refresh()
		w.dragLeft("r2", 80)
		expect(w.debug().engagedKey).toBeNil() -- locked: declined
		expect(w.debug().engineCount).toBe(0)
		w.release()
		-- ...unlocked. The cached "no actions" verdict was derived from the OLD
		-- item and must not survive it.
		w.rows:set({ { id = "r1" }, { id = "r2" }, { id = "r3" } })
		w.pres.refresh()
		w.dragLeft("r2", 80)
		expect(w.debug().engagedKey).toBe("r2")
		expect(w.debug().engineCount).toBe(1)
	end)

	it("(n) N1: a row that LOSES its actions when its item changes drops its engine", function()
		local fired: { string } = {}
		local w = world({
			count = 6,
			rowActions = function(item: any): any
				if item.locked then
					return nil
				end
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
			end,
		})
		w.rows:set({ { id = "r1" }, { id = "r2" }, { id = "r3" } })
		w.pres.refresh()
		w.dragLeft("r2", 80)
		expect(w.debug().engagedKey).toBe("r2")
		expect(w.debug().engineCount).toBe(1)
		w.release()
		w.settle()
		-- the row locks: the engine built from the unlocked item must go
		w.rows:set({ { id = "r1" }, { id = "r2", locked = true }, { id = "r3" } })
		w.pres.refresh()
		expect(w.debug().engineCount).toBe(0)
		expect(w.debug().engagedKey).toBeNil()
		w.dragLeft("r2", 80)
		expect(w.debug().engagedKey).toBeNil() -- declined now
		expect(w.debug().engineCount).toBe(0)
		expect(#fired).toBe(0)
	end)

	it("(o) N2: a pen press is declined at the down — no capture, no engine", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		local hit = rowHit("r2")
		local rect = w.adapter.node(hit).rect
		w.adapter.pointerDown(hit, rect.x + rect.w - 20, rect.y + rect.h / 2, "pen")
		w.tick(FRAME)
		expect(w.debug().engineCount).toBe(0)
		-- the capture was DECLINED, so a mouse press on another row still lands
		-- (one live capture owns the pointer)
		w.dragLeft("r4", 80)
		expect(w.debug().engagedKey).toBe("r4")
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

-- =============================================================================
--[[ TASK 4 — the shared tray overlay, the presentation slide, the commit height.
	Everything here is about what the player can actually SEE and TOUCH:
	  * the overlay mounts ONE keyed region at the engaged row's canvas offset,
	    holding that engine's OWN tray views (`row_actions`' `trayViews` — the
	    same blueprints a standalone row parents under its own root);
	  * the row's content slides through the PRESENTATION channel, so a
	    disengaged row declares no reactive offset prop at all;
	  * a released gesture now settles at the MEASURED tray width (Task 3's
	    carried item 3: with no tray there was nothing to measure and the row
	    snapped back to 0);
	  * a commit collapses the committing row's height, and only that row's;
	  * outside-dismiss, both halves — outside the list (the presenter's own
	    `outsideDismiss`) and inside it (the shared dispatcher). ]]
describe("VirtualList rowActions (Task 4): the shared tray overlay", function()
	it("(p) the overlay mounts at the engaged row's offset; the row slides by presentation", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		-- the group spans the ROW's own box: r2's slot is (2-1)*40 tall by the
		-- full row width, so a tray anchored to an edge is anchored to the row's
		local group = w.adapter.node(trayGroup("r2"))
		expect(group).never().toBeNil()
		expect(group.rect.y).toBe(40)
		expect(group.rect.h).toBe(40)
		expect(group.rect.w).toBe(800)
		-- ...with the TRAILING tray's button inside it, at the row's right edge
		local button = w.adapter.node(trayAction("r2", "trailing", "delete"))
		expect(button).never().toBeNil()
		expect(button.rect.x + button.rect.w).toBe(800)
		expect(button.rect.y).toBe(40)
		-- the leading tray is not declared on this row, so nothing mounts for it
		expect(w.adapter.node(tray("r2", "leading"))).toBeNil()

		--[[ THE SLIDE IS PRESENTATION, NOT LAYOUT (design §3). The row's SOLVED
			rect never moves — that is what makes a disengaged row free — and the
			translation lives on the presentation channel, exactly where the
			DropLine and the drag ghost already live. ]]
		local row = w.adapter.node(rowPath("r2"))
		expect(row.rect.x).toBe(0)
		expect(row.presentationOffset.x).toBe(-80)
		expect(row.presentationOffset.x).toBe(w.list.engagedOffset:get())
		-- and no OTHER row is translated
		expect(w.adapter.node(rowPath("r3")).presentationOffset.x).toBe(0)
	end)

	it("(w) a released gesture settles at the MEASURED tray width (Task 3 carried item 3)", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		--[[ THE POINT OF THIS CASE. `targetFor(edge)` reads the MEASURED tray
			width — `deriveNaturals` asking `controller.textAt` for the button at
			the host's own tray path — so before the overlay existed it was 0 and
			every release settled back to closed. The expectation is the framework
			measurement oracle at the theme's own pad/floor, never this control's
			arithmetic restated. ]]
		local expected = expectedTrayWidth(w, trayAction("r2", "trailing", "delete"), "Delete")
		expect(w.list.engagedOffset:get()).toBe(-expected)
		expect(w.debug().engagedKey).toBe("r2")
		-- ...and the number is the button's actual painted width, not a
		-- coincidence: the row is open at exactly the width of what it revealed
		local button = w.adapter.node(trayAction("r2", "trailing", "delete"))
		expect(button.rect.w).toBe(expected)
		expect(w.adapter.node(rowPath("r2")).presentationOffset.x).toBe(-expected)
	end)

	it("(u) the tray is measured against the LIST'S OWN env, not the neutral theme (Task 3 carried item 1)", function()
		--[[ `buttonPad`/`buttonMinWidth` are theme facts with no font component,
			so the engine resolves them from `spec.env`'s live `themeMetrics`.
			Before Task 4 nothing handed a hosted engine an environment at all, so
			a theme package moved the painted tray and NOT the width the row
			settles open at — the row would have stopped short of, or past, its own
			buttons. The differential is a retuned pad/floor. ]]
		local retuned = retunedRowActions(24, 30)
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		local action = trayAction("r2", "trailing", "delete")
		-- open once under the NEUTRAL theme, to have the number this must differ
		-- from (a floor-dominated retune would prove nothing about the pad at all)
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		local neutralWidth = expectedTrayWidth(w, action, "Delete")
		expect(w.list.engagedOffset:get()).toBe(-neutralWidth)
		local retunedWidth = expectedTrayWidth(w, action, "Delete", retuned)
		expect(retunedWidth ~= neutralWidth).toBe(true) -- a real differential
		w.close()

		w.env:set("themeMetrics", retuned)
		w.pres.refresh()
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		expect(w.list.engagedOffset:get()).toBe(-retunedWidth)
		-- ...and the PAINTED button agrees, which is the whole point: measured
		-- and painted are the same number under the same theme
		expect(w.adapter.node(trayAction("r2", "trailing", "delete")).rect.w).toBe(retunedWidth)
	end)

	it("(q) a tap on a tray button fires its action exactly ONCE and closes the row", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		local before = w.adapter.node(trayAction("r2", "trailing", "delete"))
		expect(before).never().toBeNil()
		--[[ The Activate arrives at the LIST's contribution (the overlay is the
			list's own subtree, and a hosted engine has no node for the presenter to
			walk to), and the list hands it to the engaged engine, whose
			`_handleActivate` matches under the tray path this control gave it. ]]
		w.adapter.tap(trayAction("r2", "trailing", "delete"))
		w.settle()
		expect(fired).toEqual({ "r2" })
		-- a tray tap is NOT a row activate
		expect(w.activations).toEqual({})
		-- ...and the row closed behind it: overlay gone, slide restored
		expect(w.debug().engagedKey).toBeNil()
		expect(w.list.engagedOffset:get()).toBe(0)
		expect(w.adapter.node(trayGroup("r2"))).toBeNil()
		expect(w.adapter.node(rowPath("r2")).presentationOffset.x).toBe(0)
	end)

	it("(r) disengaging unmounts the overlay, clears the slide, and returns the tree to the closed shape", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		local closed = #w.adapter.paths()
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		expect(#w.adapter.paths() > closed).toBe(true)
		expect(w.adapter.node(trayGroup("r2"))).never().toBeNil()
		w.close()
		expect(w.debug().engagedKey).toBeNil()
		expect(w.list.engagedOffset:get()).toBe(0)
		expect(w.adapter.node(trayGroup("r2"))).toBeNil()
		-- the tree is the CLOSED tree again, node for node
		expect(#w.adapter.paths()).toBe(closed)
		-- ...and the slide is CLEARED, not merely zeroed somewhere else
		expect(w.adapter.node(rowPath("r2")).presentationOffset.x).toBe(0)
	end)

	it("(x) engagement moving straight from one row to another repaints the overlay for the NEW row", function()
		--[[ WHY THE OVERLAY IS A KEYED REGION AND NOT A `UI.When`. Swiping r4
			while r2 is open switches `engagedKey` r2 -> r4 with no nil in between
			(r4 drives the live gesture; r2 is merely finishing its close). A
			`When`'s branch factory runs only on false -> true, so the overlay would
			have gone on painting r2's actions over r4's row for as long as r4
			stayed open. ]]
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		expect(w.adapter.node(trayGroup("r2"))).never().toBeNil()
		w.dragLeft("r4", 80)
		expect(w.debug().engagedKey).toBe("r4")
		expect(w.adapter.node(trayGroup("r2"))).toBeNil()
		local group = w.adapter.node(trayGroup("r4"))
		expect(group).never().toBeNil()
		expect(group.rect.y).toBe(120) -- (4-1) * 40: r4's own slot, not r2's
		expect(w.adapter.node(trayAction("r4", "trailing", "delete"))).never().toBeNil()
		-- ...and the slide moved with it: r2 is flat again, r4 is translated
		expect(w.adapter.node(rowPath("r2")).presentationOffset.x).toBe(0)
		expect(w.adapter.node(rowPath("r4")).presentationOffset.x).toBe(-80)
	end)

	it("(v1) a tap OUTSIDE the list closes the open row, and does not swallow that tap", function()
		--[[ The presenter's own `outsideDismiss`, contributed by the list: it
			compares the tapped path against THIS CONTRIBUTION's path, so "outside"
			means outside the whole list. `consume = false` (verbatim from the
			engine's own seam) means the tap that closed the tray still does what it
			was going to do — row-actions' round-7 rule: closing must never swallow
			an unrelated click. ]]
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired), sibling = true })
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		expect(w.debug().engagedKey).toBe("r2")
		w.adapter.tap("/S/Outside")
		w.settle()
		expect(w.debug().engagedKey).toBeNil()
		expect(w.adapter.node(trayGroup("r2"))).toBeNil()
		expect(w.activations).toEqual({ "outside" }) -- NOT swallowed
		expect(#fired).toBe(0)
	end)

	it("(v2) a press on ANOTHER row closes the open one, and still activates the row pressed", function()
		--[[ THE IN-LIST HALF. Every row is inside the ONE list contribution, so
			the presenter's outside-tap path can never see this — Table gets it free
			only because its rows each contribute separately. The shared dispatcher
			says it instead, on the down, without swallowing the press. ]]
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		w.adapter.touchTap(rowHit("r5"))
		w.settle()
		expect(w.debug().engagedKey).toBeNil()
		expect(w.adapter.node(trayGroup("r2"))).toBeNil()
		expect(w.activations).toEqual({ "r5" })
		expect(#fired).toBe(0)
	end)

	it("(v3) a tap on the OPEN row's own slid content closes it, and fires no activate", function()
		-- iOS parity: with a tray open, a tap on the row means "put it away" and
		-- means only that — the alternative is swipe-then-tap opening whatever the
		-- row's own `onActivate` opens.
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		w.adapter.touchTap(rowHit("r2"))
		w.settle()
		expect(w.debug().engagedKey).toBeNil()
		expect(w.list.engagedOffset:get()).toBe(0)
		expect(w.activations).toEqual({})
		expect(#fired).toBe(0)
		-- ...and the row is an ordinary row again: the NEXT tap activates
		w.adapter.touchTap(rowHit("r2"))
		expect(w.activations).toEqual({ "r2" })
	end)

	it("(s) a destructive commit collapses THAT row's height, and only that row's", function()
		local fired: { string } = {}
		local w = world({
			rowActions = function(item: any): any
				return {
					trailing = {
						{
							id = "delete",
							label = "Delete",
							role = "destructive",
							onAction = function()
								table.insert(fired, item.id)
							end,
						},
					},
				}
			end,
		})
		local rect = w.adapter.node(rowHit("r2")).rect
		w.dragLeft("r2", rect.w * 0.75) -- past 60% of the row
		w.release()
		-- run to the frame the collapse is actually visible on
		local collapsedAt: number? = nil
		for i = 1, 400 do
			w.tick(FRAME)
			if w.adapter.node(rowPath("r2")).rect.h < 40 then
				collapsedAt = i
				break
			end
		end
		expect(collapsedAt).never().toBeNil()
		local collapsed = w.adapter.node(rowPath("r2")).rect.h
		expect(collapsed < 40).toBe(true)
		-- ONLY that row: every other row keeps the list's uniform height, and the
		-- slots do not move (the canvas is index x pitch — a virtual list's
		-- geometry, unlike a stack's, does not close the gap)
		expect(w.adapter.node(rowPath("r1")).rect.h).toBe(40)
		expect(w.adapter.node(rowPath("r3")).rect.h).toBe(40)
		expect(w.adapter.node(rowPath("r3")).rect.y).toBe(80)
		-- ...and the tray collapses WITH the row it belongs to
		expect(w.adapter.node(trayGroup("r2")).rect.h).toBe(collapsed)
		-- the ladder finishes: the action fires once and the override is released
		w.settle(400)
		expect(fired).toEqual({ "r2" })
		expect(w.adapter.node(rowPath("r2")).rect.h).toBe(40)
		expect(w.debug().engagedKey).toBeNil()
	end)

	it("(y) the PHANTOM ROW: a fired commit's return flight keeps its tray and takes no gesture", function()
		--[[ The consumer that does NOT remove a destructively-committed row
			(row_actions' own redteam item 5). Between the fire and the row
			arriving home, `commitLatched` refuses every new gesture — so the
			question Task 4 has to answer is what the OVERLAY does in that window.

			It paints the tray, and that is deliberate: the overlay parents the
			ENGINE's own tray views, whose reveal memo is `openEdge`, falling back
			to the SIGN of `offset` — the same rule a standalone row uses, for the
			same reason (a row still visibly off its rest position has visibly
			vacated the strip the tray occupies; blanking it would flash empty
			space under a sliding row). No extra guard, and none wanted: parity
			with standalone/Table is the specification here. ]]
		local fired: { string } = {}
		local w = world({
			rowActions = function(item: any): any
				return {
					trailing = {
						{
							id = "delete",
							label = "Delete",
							role = "destructive",
							onAction = function()
								table.insert(fired, item.id) -- and the row STAYS in the data
							end,
						},
					},
				}
			end,
		})
		local rect = w.adapter.node(rowHit("r2")).rect
		w.dragLeft("r2", rect.w * 0.75)
		w.release()
		for _ = 1, 400 do
			w.tick(FRAME)
			if #fired == 1 then
				break
			end
		end
		expect(fired).toEqual({ "r2" })
		-- parked mid-flight, and the tray is still there with it
		expect(w.list.engagedOffset:get() < -rect.w * 0.5).toBe(true)
		expect(w.adapter.node(trayGroup("r2"))).never().toBeNil()
		expect(w.adapter.node(trayAction("r2", "trailing", "delete"))).never().toBeNil()
		-- ...and the latched row takes no new gesture (D1's own guard, unchanged)
		w.dragLeft("r2", 40)
		expect(w.list.engagedOffset:get() < -rect.w * 0.5).toBe(true)
		w.release()
		w.settle(400)
		expect(fired).toEqual({ "r2" }) -- still exactly one
		expect(w.debug().engagedKey).toBeNil()
		expect(w.adapter.node(trayGroup("r2"))).toBeNil()
	end)

	it("(z) an open row that unmounts and comes back is still slid", function()
		--[[ THE RENDERER FORGETS a path's presentation transform when that path is
			removed (`lastTransform` is cleared on removal, renderer.luau) — so a
			signal-driven-only slide would leave a row that left the window and came
			back painted FLAT while this control still believed it was translated,
			with no further write coming (the engagement never moved). Reachable
			without any scroll at all: a LIVE viewport that shrinks past the open row
			and grows again — and a scroll would not do, because a scroll closes the
			open row through the coordinator before it can leave. The slide is
			re-asserted every sync pass, which is what heals it. ]]
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired), liveViewport = 400 })
		local height = w.viewportHeight
		expect(w.list.debugWindow().r12).toBe(true) -- 10 visible + 2 overscan
		w.dragLeft("r12", 80)
		w.release()
		w.settle()
		local open = w.list.engagedOffset:get()
		expect(open < 0).toBe(true)
		expect(w.adapter.node(rowPath("r12")).presentationOffset.x).toBe(open)
		-- the viewport shrinks past r12: the row unmounts, and NOTHING closes it
		-- (no scroll happened)
		height:set(120)
		w.pres.refresh()
		expect(w.list.debugWindow().r12).toBeNil()
		expect(w.debug().engagedKey).toBe("r12")
		-- ...and it comes back still slid
		height:set(400)
		w.pres.refresh()
		expect(w.list.debugWindow().r12).toBe(true)
		expect(w.adapter.node(rowPath("r12")).presentationOffset.x).toBe(open)
	end)

	it("(t) a FULL SWIPE commits end-to-end on the mounted tree", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		local closed = #w.adapter.paths()
		local rect = w.adapter.node(rowHit("r2")).rect
		w.dragLeft("r2", rect.w * 0.75)
		-- mid-swipe the tray is mounted and the row is translated past the tray's
		-- own width — the full-swipe reveal, not merely the open one
		expect(w.adapter.node(trayGroup("r2"))).never().toBeNil()
		expect(w.adapter.node(rowPath("r2")).presentationOffset.x).toBe(-rect.w * 0.75)
		w.release()
		w.settle(400)
		expect(fired).toEqual({ "r2" })
		-- and the tree is back to the closed shape, slide cleared
		expect(#w.adapter.paths()).toBe(closed)
		expect(w.adapter.node(rowPath("r2")).presentationOffset.x).toBe(0)
		expect(w.debug().engagedKey).toBeNil()
	end)
end)
