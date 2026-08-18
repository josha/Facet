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

local Facet = require("../src") :: any
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

-- ...and the distance the ROW travels to uncover that plate, which is NOT the
-- same number (device bug round 2026-08-12, finding A1a): the band carries the
-- theme's own row-facing gutter — `controls.rowActions.rowGutter`, the negative
-- space that keeps the plate off the row it is acting on — and the row has to
-- travel far enough to uncover that too, exactly as it already had to for
-- `trayGap`. Resolved from the same snapshot the tray was measured against, so a
-- retuned theme moves both halves together.
local function expectedTravel(w: any, path: string, label: string, metrics: any?): number
	local snap = metrics or themeSnapshot.neutral()
	local gutter = themeSnapshot.resolveNumber(snap, "controls.rowActions.rowGutter") or 0
	return expectedTrayWidth(w, path, label, metrics) + gutter
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
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local clockTime = 0
	-- KEYBOARD NAVIGATION IS OPT-IN at the presenter (director playtest
	-- 2026-08-03), so only the Tab case asks for it — everything else drives the
	-- arrows/d-pad, which every surface answers.
	local presenterOpts: any = {
		now = function()
			return clockTime
		end,
	}
	if options.keyboardNavigation ~= nil then
		presenterOpts.keyboardNavigation = options.keyboardNavigation
	end
	local pres = Facet.newPresenter(core, env, adapter, system, presenterOpts)
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
			return Facet.UI.Text({ id = "Label", text = item.label, textSize = 14 })
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
	-- the list's own focus-group overrides ({ name?, wrap?, containment?, entry?,
	-- exit? }) and the live focus-skip predicate — both public spec keys, both
	-- unplumbed here until the tray got a group of its own to collide with them
	if options.navigation ~= nil then
		spec.navigation = options.navigation
	end
	if options.rowFocusable ~= nil then
		spec.rowFocusable = options.rowFocusable
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
	local list = virtual_list.build(Facet, core, spec)
	local children: { any } = { list.blueprint }
	if options.sibling then
		-- a rendered node OUTSIDE the list, for the outside-tap half of dismiss
		table.insert(
			children,
			Facet.UI.Button({
				id = "Outside",
				label = "Outside",
				onActivate = function()
					table.insert(activations, "outside")
				end,
			})
		)
	end
	local screen = Facet.UI.Screen({ id = "S", children = children })
	local handle = pres.present(screen)
	pres.refresh()
	local unbindScroll = list.bindNativeScroll(handle.controller)

	local w: any = {
		core = core,
		env = env,
		viewportHeight = viewportHeight,
		adapter = adapter,
		system = system,
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
	--[[ THE SAME SWIPE, RIGHTWARD: the LEADING edge's gesture. Starts near the
		row's left edge so a full-width drag has somewhere to go, and every sign is
		mirrored — a positive `engagedOffset` is a leading reveal. ]]
	function w.dragRight(key: string, dx: number, pointerType: string?)
		local hit = rowHit(key)
		local rect = adapter.node(hit).rect
		local originX = rect.x + 20
		local y = rect.y + rect.h / 2
		adapter.pointerDown(hit, originX, y, pointerType or "mouse")
		w.tick(FRAME)
		adapter.pointerMove(originX + (LOCK + 2), y)
		w.tick(FRAME)
		adapter.pointerMove(originX + dx, y)
		w.tick(FRAME)
		lastPos = { x = originX + dx, y = y }
	end
	--[[ A SWIPE WITH NO FLICK IN IT — the idiom the standalone suite's own
		threshold cases use (tests/row_actions_input.spec.luau, "release under
		half-tray snaps closed"): cross the axis lock in ONE move and then hold
		still for a whole second, so the velocity tracker has decayed to ~0 by the
		release and the settle verdict is the OFFSET's alone. `dragLeft`'s
		three-move shape ends on a 20px-per-frame move, which projects a flick and
		would open a row the test meant to snap back. ]]
	function w.dragLeftNoFlick(key: string, dx: number)
		local hit = rowHit(key)
		local rect = adapter.node(hit).rect
		local originX = rect.x + rect.w - 20
		local y = rect.y + rect.h / 2
		adapter.pointerDown(hit, originX, y, "mouse")
		w.tick(0.01)
		adapter.pointerMove(originX - dx, y) -- one move, past the lock
		w.tick(1.0)
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
	--[[ THE RELEASE THE ENGINE ACTUALLY PERFORMS (redteam NEW-1, 2026-08-13).
		A hosted row's `Hit` is a real `GuiButton`, so the same gesture that swipes
		it also ends in that button's `Activated` — on either side of `InputEnded`.
		`w.release()` above is the SILENT release (an up landing off the translated
		hit), and until this existed it was the only release this whole file could
		drive: every hosted swipe case here proved the control against a sequence
		the engine does not produce, which is exactly why a defect that fired
		`onActivate` on EVERY swipe survived 2000 lines of hosted specs.
		`fake_target.pointerUpActivating` delivers the real thing, with the full
		pointer meta. ]]
	function w.releaseActivating(order: "before" | "after")
		adapter.pointerUpActivating(lastPos.x, lastPos.y, order)
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

-- one "Flag" leading and one "Delete" trailing per row — the both-edges list.
-- MODULE SCOPE, because two describes need it: Task 5's parity block and the
-- release-Activate matrix at the bottom of this file.
local function bothEdges(fired: { string }, role: string?): (item: any) -> any
	return function(item: any): any
		return {
			leading = {
				{
					id = "flag",
					label = "Flag",
					onAction = function()
						table.insert(fired, `flag:{item.id}`)
					end,
				},
			},
			trailing = {
				{
					id = "delete",
					label = "Delete",
					role = role,
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
		local core = Facet.newCore()
		local ok, err = pcall(function()
			virtual_list.build(Facet, core, {
				id = "VL",
				rows = core:signal(makeRows(4)),
				key = function(item: any)
					return item.id
				end,
				rowHeight = 40,
				viewportHeight = 200,
				cell = function(item: any)
					return Facet.UI.Text({ id = "L", text = item.label })
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

	it("(d) MOUNT IDENTITY: a hosted list adds exactly ONE node, and no pointer surface per row", function()
		--[[ THE FULL DIFFERENTIAL LIVES IN tests/virtual_list_row_actions_identity.spec.luau
			— one builder, two worlds, every shared node compared in every recorded
			field (class, rect, props, elision, handler slots) and over five
			engage/disengage cycles. It is deliberately NOT restated here: this file
			had a class+rect copy of it, which is a second place to keep in step and
			a second place to share the same blind spot (a per-row modifier prop
			passes class+rect untouched).

			What stays here is the claim this file's own cases lean on: the hosted
			tree is the plain tree plus the ONE overlay node, and a closed hosted row
			is not a pointer-capture surface until the dispatcher rides its hit. ]]
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
		local extra: { string } = {}
		for path in b do
			if a[path] == nil then
				table.insert(extra, path)
			end
		end
		expect(extra).toEqual({ "/S/VL/Canvas/RowActionsOverlay" })
		for path in a do
			expect(b[path]).toBe(true)
		end
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
		local screen2 = Facet.UI.Screen({ id = "S2", children = { w.blueprint } })
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
		local deepest = 0
		for i = 1, 400 do
			w.tick(FRAME)
			deepest = math.min(deepest, w.list.engagedOffset:get())
			if #fired == 1 then
				firedAt = i
				break
			end
		end
		expect(firedAt).never().toBeNil()
		-- THE ROW REALLY WAS CARRIED OFF, asserted over the whole trace rather than
		-- at the fire frame. It used to still BE there at the fire frame, because the
		-- chain fired and then sprang the row home over ~65 more frames — the second
		-- half of device finding C8a ("the row reappears quickly before the delete
		-- happens"), now deferred to the next sync and snapped rather than flown. See
		-- the standalone mirror in tests/row_actions_input.spec.luau for the full
		-- note; the guarantee this case exists for — exactly one fire — is unchanged.
		expect(deepest).toBeLessThan(-rect.w * 0.5)
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
		local travel = expectedTravel(w, trayAction("r2", "trailing", "delete"), "Delete")
		expect(w.list.engagedOffset:get()).toBe(-travel)
		expect(w.debug().engagedKey).toBe("r2")
		-- ...and the number is the button's actual painted width, not a
		-- coincidence: the row is open at exactly the width of what it revealed
		local button = w.adapter.node(trayAction("r2", "trailing", "delete"))
		expect(button.rect.w).toBe(expected)
		expect(w.adapter.node(rowPath("r2")).presentationOffset.x).toBe(-travel)
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
		expect(w.list.engagedOffset:get()).toBe(-expectedTravel(w, action, "Delete"))
		local retunedWidth = expectedTrayWidth(w, action, "Delete", retuned)
		expect(retunedWidth ~= neutralWidth).toBe(true) -- a real differential
		w.close()

		w.env:set("themeMetrics", retuned)
		w.pres.refresh()
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		expect(w.list.engagedOffset:get()).toBe(-expectedTravel(w, action, "Delete", retuned))
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
		-- ...and the OVERLAY moved with it, which is what this case is about.
		expect(w.adapter.node(rowPath("r4")).presentationOffset.x).toBe(-80)
		--[[ RE-BASELINED 2026-08-15, deliberately, and it is the carried defect
			going away rather than a characterization being weakened. This line used
			to read `…node(rowPath("r2")).presentationOffset.x).toBe(0)` with the
			comment "r2 is flat again" — and that WAS the shipped behavior, recorded
			as a defect in both `virtual_list.luau`'s own slide-seam comment
			("Device-pass rider: iOS animates the previously-open row closed under it;
			hosted mode jumps it") and in `docs/plans/table-hosted-row-actions-stage2.md`
			§"three open hosted-mode defects", item 2 — "a visible regression on a
			shipped Table surface, not a theoretical one", because Table animates it
			today and a hosted Table would have inherited the jump.

			r2 lost ENGAGEMENT on the frame r4 took it, but r2's own close spring is
			still in flight: its engine is still counting down its own offset and
			still calling `onSlide`. The paint now follows the engine instead of the
			engagement, so r2 is mid-flight here, not flat — strictly between its
			open offset and home, and on the way home. ]]
		local r2 = w.adapter.node(rowPath("r2")).presentationOffset.x
		expect(r2).toBeLessThan(0) -- still translated: it is animating, not snapped
		expect(r2).toBeGreaterThan(-80) -- ...and already on its way back
		w.settle()
		expect(w.adapter.node(rowPath("r2")).presentationOffset.x).toBe(0) -- it arrives
		expect(w.adapter.node(rowPath("r4")).presentationOffset.x).toBe(-80) -- r4 held open
	end)

	--[[ (x2) THE CARRIED DEFECT ITSELF, as its own case rather than as a rider on
		the overlay's (`docs/plans/table-hosted-row-actions-stage2.md` §"three open
		hosted-mode defects", item 2 — the one the plan calls "a visible regression
		on a shipped Table surface"). (x) above proves the row is not flat on the
		handover frame; this proves the whole flight is a CLOSE, monotonically, the
		way a standalone/Table row's own spring already does it.

		WHY IT WAS BROKEN: `hostedWriteSlide` painted only the ENGAGED row, and
		engagement is a single-slot arbitration (`hostedApplySlide`) that r4 wins the
		instant it starts driving. r2's pixels went on being computed and were simply
		not written. The fix is the smallest one that is honest about what the two
		things are: engagement is who owns the TRAY (the coordinator's one-open
		policy makes that genuinely singular); the SLIDE is per row, because two
		springs really are in flight at once. ]]
	it("(x2) the row that loses engagement animates closed under the new one, monotonically", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		-- settled OPEN at the band's own width (not the 80px drag) — read, not
		-- hard-coded, because the width is the theme's measurement, not this case's
		local openPx = w.adapter.node(rowPath("r2")).presentationOffset.x
		expect(openPx).toBeLessThan(0)

		w.dragLeft("r4", 80) -- r4 claims the coordinator; r2 is closed by it
		local samples: { number } = {}
		for _ = 1, 40 do
			w.tick(FRAME)
			table.insert(samples, w.adapter.node(rowPath("r2")).presentationOffset.x)
		end
		-- it MOVED, over more than one frame — a snap would have put 0 in every
		-- sample including the first
		expect(samples[1]).never().toBe(0)
		expect(samples[#samples]).toBe(0)
		-- ...and it only ever went one way: no overshoot past home, no re-open
		for i = 2, #samples do
			expect(samples[i]).toBeGreaterThanOrEqual(samples[i - 1])
			expect(samples[i]).toBeLessThanOrEqual(0)
		end
		-- at least one intermediate frame that is neither the start nor home:
		-- that is the animation this case exists for
		local intermediates = 0
		for _, px in samples do
			if px < 0 then
				intermediates += 1
			end
		end
		expect(intermediates).toBeGreaterThan(1)
		-- and r4, the row that took the engagement, is unaffected throughout
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

	--[[ (v2b)/(v2c) F1 (review round 1). The in-list dismiss used to sit BELOW
		both of this dispatcher's declines, so a press that could never become a
		gesture never closed anything: on a MIXED list — some rows actionable,
		some not, which is the whole reason `rowActions(item)` may answer nil —
		pressing an actionless row left the tray open and the row slid, with no
		way back except pressing an actionable row. Dismissal has nothing to do
		with whether this press can become a gesture, and now says so. ]]
	local function mixedList(fired: { string }): (item: any) -> any
		return function(item: any): any
			if item.id == "r5" then
				return nil -- an actionless row, in the middle of actionable ones
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
		end
	end

	it("(v2b) F1: pressing an ACTIONLESS row closes the open one", function()
		local fired: { string } = {}
		local w = world({ rowActions = mixedList(fired) })
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		expect(w.debug().engagedKey).toBe("r2")
		-- r5 has no actions: it declines the capture, builds nothing — and still
		-- puts the open tray away
		w.adapter.touchTap(rowHit("r5"))
		w.settle()
		expect(w.debug().engagedKey).toBeNil()
		expect(w.list.engagedOffset:get()).toBe(0)
		expect(w.adapter.node(trayGroup("r2"))).toBeNil()
		expect(w.adapter.node(rowPath("r2")).presentationOffset.x).toBe(0)
		-- ...and the actionless row is still an ordinary row: it activated, and
		-- no engine was built for it
		expect(w.activations).toEqual({ "r5" })
		expect(w.debug().engineCount).toBe(1) -- r2's, and only r2's
		expect(#fired).toBe(0)
	end)

	it("(v2c) F1: a PEN press closes the open row too, and is still declined", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		local hit = rowHit("r5")
		local rect = w.adapter.node(hit).rect
		w.adapter.pointerDown(hit, rect.x + rect.w - 20, rect.y + rect.h / 2, "pen")
		w.settle()
		expect(w.debug().engagedKey).toBeNil()
		expect(w.adapter.node(trayGroup("r2"))).toBeNil()
		-- the DECLINE still holds (N2): no engine was built for the pen's row,
		-- and the capture was never taken — a mouse press on another row lands
		expect(w.debug().engineCount).toBe(1)
		w.dragLeft("r4", 80)
		expect(w.debug().engagedKey).toBe("r4")
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

	it("(y) the PHANTOM ROW: a fired commit leaves nothing standing, and the row is reusable", function()
		--[[ The consumer that does NOT remove a destructively-committed row
			(row_actions' own redteam item 5) — the "phantom row" case. What the
			OVERLAY does through the commit is the question Task 4 had to answer.

			THE ANSWER CHANGED, and it changed because the game director filmed the
			old one (device bug round 2026-08-12, finding C8a — "the row goes fully
			away but the delete/flag buttons show up and then animate away
			vertically? That's odd — the row should just go away", plus "then the row
			reappears quickly before the delete happens").

			It USED to paint the tray for the commit's whole duration, on the
			argument that a row visibly off its rest position has visibly vacated the
			strip the tray occupies. Measured, that argument does not survive: the
			band stood fully painted for 95 frames (1.58 s) on a row that was
			entirely off-screen, and was then squashed vertically as the height
			collapsed. And when the chain finished it put the row's paint back — full
			height, springing home from a whole row width out — before the owner had
			a chance to remove it.

			Both are fixed in the SHARED engine (`committingSig` and the deferred
			`finishCommit` restore, src/controls/row_actions.luau), so this case now
			asserts the new contract, which is still parity with standalone/Table:
			a destructive commit carries the row off, leaves NOTHING standing where
			it was, and puts a surviving row back with a snap rather than a flight.
			The guarantees this case was written for are all still here — one fire,
			the latched row refusing a new gesture, and a clean end state. ]]
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
		local rowHeight = w.adapter.node(rowPath("r2")).rect.h
		w.dragLeft("r2", rect.w * 0.75)
		w.release()
		local deepest = 0
		local carriedClear = false
		for _ = 1, 400 do
			w.tick(FRAME)
			deepest = math.min(deepest, w.list.engagedOffset:get())
			-- ...once the row itself has been carried clear, NOTHING may still be
			-- painted in the strip it left (C8a's first half)
			if w.list.engagedOffset:get() <= -rect.w * 0.95 then
				carriedClear = true
				expect(w.adapter.node(trayAction("r2", "trailing", "delete"))).toBeNil()
			end
			if carriedClear and #fired == 0 then
				break -- parked off-row with the collapse still playing: still LATCHED
			end
			if #fired == 1 then
				break
			end
		end
		expect(carriedClear).toBe(true)
		expect(deepest).toBeLessThan(-rect.w * 0.5) -- it really was carried a row width out
		--[[ THE LATCHED ROW TAKES NO NEW GESTURE (D1's own guard, unchanged, and now
			exercised where the latch actually lives). The window used to be the
			RETURN FLIGHT after the fire, and that flight no longer exists — a
			surviving row is snapped home on the next sync instead (device finding
			C8a's second half). The latch itself is unchanged and still covers the
			whole commit, so the press is made HERE, with the row parked off-row and
			the collapse still playing: exactly the state whose live `offset` used to
			seed `drag.startOffset` past the commit threshold. ]]
		w.dragLeft("r2", 40)
		w.release()
		-- refused: the row is still off-row, exactly where the commit put it. (Not an
		-- equality: the slide-off spring is still finishing, so the number moves —
		-- what must not happen is the gesture taking the row over.)
		expect(w.list.engagedOffset:get()).toBeLessThan(-rect.w * 0.9)
		w.settle(400)
		expect(fired).toEqual({ "r2" }) -- still exactly one
		expect(w.debug().engagedKey).toBeNil()
		expect(w.adapter.node(trayGroup("r2"))).toBeNil()
		-- ...and a row the owner kept is a NORMAL row again: full height, at rest
		expect(w.adapter.node(rowPath("r2")).rect.h).toBe(rowHeight)
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

-- =============================================================================
--[[ TASK 5 — BEHAVIOR PARITY WITH THE STANDALONE SUITE, and the seam fixes the
	parity sweep found. Hosted mode reuses the SHARED engine (`buildHosted`), so
	these cases are not re-tests of `row_actions_state`'s arithmetic: they prove
	the semantics survive the HOST — the shared dispatcher, the one overlay, the
	presentation slide and the list's own Activate/focus contribution — because
	every one of those is a place a verdict can be lost on the way to the player.

	WHAT IS ALREADY PROVEN ABOVE, and is therefore not restated here (the parity
	list's own items, audited case by case):
	  * fullSwipe commit end-to-end — (t), with the destructive collapse in (s),
	    the double-commit guard in (l) and the return flight in (y);
	  * the one-open policy mid-gesture — (b2)/(x);
	  * outside-tap and in-list dismissal — (v1), (v2), (v2b), (v2c), (v3);
	  * scroll-close — (e).

	WHAT THIS BLOCK ADDS: both edges, the open/snap-back threshold with no flick
	in the gesture, `fullSwipe = false`, the three irrevocable-commit probes
	against the HOST's own close paths, the settled one-open handoff, keyboard
	Delete (with its lazy-engine gap named), focus TRAVERSAL into a revealed tray
	(the fix in `buildFocusGroups`), and the ACTIVATE-SEAM close (the fix in
	`handleActivate`). ]]
describe("VirtualList rowActions (Task 5): behavior parity", function()
	-- a row with BOTH edges declared, and a destructive `role` on request
	local function destructiveActions(fired: { string }): (item: any) -> any
		return function(item: any): any
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
		end
	end

	it("(P1) both edges reveal: a leftward swipe opens the TRAILING tray, a rightward one the LEADING", function()
		local fired: { string } = {}
		local w = world({ rowActions = bothEdges(fired) })
		-- TRAILING: the row slides left, and only the trailing tray mounts
		w.dragLeft("r2", 60)
		w.release()
		w.settle()
		expect(w.debug().engagedKey).toBe("r2")
		expect(w.list.engagedOffset:get() < 0).toBe(true)
		expect(w.adapter.node(trayAction("r2", "trailing", "delete"))).never().toBeNil()
		expect(w.adapter.node(tray("r2", "leading"))).toBeNil()
		expect(w.list.engagedOffset:get()).toBe(-expectedTravel(w, trayAction("r2", "trailing", "delete"), "Delete"))
		w.close()

		-- LEADING: the same row, the other direction — mirrored sign, and the
		-- tray that mounts is the other one
		w.dragRight("r2", 60)
		w.release()
		w.settle()
		expect(w.debug().engagedKey).toBe("r2")
		expect(w.list.engagedOffset:get() > 0).toBe(true)
		expect(w.adapter.node(trayAction("r2", "leading", "flag"))).never().toBeNil()
		expect(w.adapter.node(tray("r2", "trailing"))).toBeNil()
		expect(w.list.engagedOffset:get()).toBe(expectedTravel(w, trayAction("r2", "leading", "flag"), "Flag"))
		-- the leading tray is anchored at the row's LEFT edge, where it was revealed
		expect(w.adapter.node(trayAction("r2", "leading", "flag")).rect.x).toBe(0)
		-- ...and the leading action is the one that fires
		w.adapter.tap(trayAction("r2", "leading", "flag"))
		w.settle()
		expect(fired).toEqual({ "flag:r2" })
	end)

	it("(P2) the OPEN THRESHOLD: a release past half the tray width settles open, under it snaps back", function()
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		-- learn the tray width from the framework's own oracle, so the two drags
		-- below straddle a number this test never guessed
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		local travel = expectedTravel(w, trayAction("r2", "trailing", "delete"), "Delete")
		expect(w.list.engagedOffset:get()).toBe(-travel)
		w.close()

		-- UNDER half, with no flick in the gesture: back to closed, tray gone
		local short = travel * 0.4
		expect(short > LOCK).toBe(true) -- still a real horizontal gesture
		w.dragLeftNoFlick("r2", short)
		expect(w.list.engagedOffset:get()).toBeCloseTo(-short, 0.001) -- it tracked the finger...
		w.release()
		w.settle()
		expect(w.debug().engagedKey).toBeNil() -- ...and then snapped back
		expect(w.list.engagedOffset:get()).toBe(0)
		expect(w.adapter.node(trayGroup("r2"))).toBeNil()

		-- PAST half, same shape of gesture: settles open at the measured width
		w.dragLeftNoFlick("r2", travel * 0.7)
		w.release()
		w.settle()
		expect(w.debug().engagedKey).toBe("r2")
		expect(w.list.engagedOffset:get()).toBe(-travel)
	end)

	it("(P2b) REGRESSION: every later short swipe on the SAME row also snaps back (the reused spring)", function()
		--[[ FOUND BY THIS PARITY SWEEP, and it was in the SHARED engine — so
			standalone rows and Table's own rows had it too (reproduced there
			before the fix: three short swipes left a standalone row at 0, -20,
			-40). A live drag drives `offset` directly after stopping the
			persistent spring, and `ensureSpring` seeds a spring only when it
			CREATES one — so from the second gesture onward the spring stood where
			the last flight left it. A snap-back aims it at 0, which is exactly
			where it already was: no steps, no writes, and the row stayed parked at
			the drag's last offset with `engagedKey` still set and no tray to close
			it. Fixed by re-seeding at the drag's end (`spring:snap(offset:get())`,
			src/controls/row_actions.luau), mirroring the collapse spring's own
			re-seed.

			The FIRST swipe was always correct, which is why the whole suite was
			green: every existing case swipes a fresh row once. ]]
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		local travel: number? = nil
		for _ = 1, 3 do
			w.dragLeftNoFlick("r2", 30) -- a real gesture, under the open threshold
			expect(w.list.engagedOffset:get()).toBeCloseTo(-30, 0.001)
			w.release()
			w.settle()
			-- ...back to rest, EVERY time — never 30px further out than last time
			expect(w.list.engagedOffset:get()).toBe(0)
			expect(w.debug().engagedKey).toBeNil()
			expect(w.adapter.node(trayGroup("r2"))).toBeNil()
			expect(w.adapter.node(rowPath("r2")).presentationOffset.x).toBe(0)
		end
		-- and the row still OPENS normally afterwards (the re-seed did not cost
		-- the spring its aim)
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		travel = expectedTravel(w, trayAction("r2", "trailing", "delete"), "Delete")
		expect(w.list.engagedOffset:get()).toBe(-(travel :: number))
		expect(#fired).toBe(0)
	end)

	it("(P2c) REGRESSION: an INTERRUPTED drag on a re-used row springs back too", function()
		--[[ The other end a manual drag can have: the engine cancels the capture
			(the Roblox menu opening — `adapter.interruptCapture` is that seam), and
			row_actions answers a horizontal cancel with `close()`. That close
			retargets the same persistent spring, so it had the same stale-seed hole
			as the release path and is re-seeded at the same moment. Proven on a row
			that has ALREADY been opened and closed once, because that is what parks
			the spring at 0 in the first place. ]]
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		w.close()
		expect(w.list.engagedOffset:get()).toBe(0)

		w.dragLeftNoFlick("r2", 30)
		expect(w.list.engagedOffset:get()).toBeCloseTo(-30, 0.001)
		w.adapter.interruptCapture()
		w.settle()
		expect(w.list.engagedOffset:get()).toBe(0) -- not left parked at -30
		expect(w.debug().engagedKey).toBeNil()
		expect(w.adapter.node(trayGroup("r2"))).toBeNil()
		expect(w.adapter.node(rowPath("r2")).presentationOffset.x).toBe(0)
		expect(#fired).toBe(0)
	end)

	it("(P3) fullSwipe = false: a full swipe past the commit threshold refuses to commit and settles OPEN", function()
		--[[ The standalone mirror is "fullSwipe = { trailing = false } refuses to
			commit on trailing". Hosted mode passes `fullSwipe` straight through to
			the shared engine, so what this proves is the HANDOFF: the spec field
			survives `rowActions(item)` -> `buildHosted`, and the row that would
			have committed is left open with its action unfired. ]]
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
					fullSwipe = { trailing = false },
				}
			end,
		})
		local rect = w.adapter.node(rowHit("r2")).rect
		w.dragLeft("r2", rect.w * 0.75) -- past 60% of the row: a commit gesture
		w.release()
		w.settle(400)
		expect(fired).toEqual({}) -- NOT committed
		expect(w.debug().engagedKey).toBe("r2") -- left open instead
		expect(w.list.engagedOffset:get()).toBe(-expectedTravel(w, trayAction("r2", "trailing", "delete"), "Delete"))
		-- ...and the row never collapsed on the way (a commit's own signature)
		expect(w.adapter.node(rowPath("r2")).rect.h).toBe(40)
		-- the action is still reachable the ordinary way (a destructive tap runs
		-- the whole slide-off/collapse ladder before it fires — case (s)'s length)
		w.adapter.tap(trayAction("r2", "trailing", "delete"))
		w.settle(400)
		expect(fired).toEqual({ "r2" })
	end)

	--[[ (P4)/(P5)/(P6) THE IRREVOCABLE COMMIT, through the HOST's own close paths.
		A destructive commit in flight owns the row: `close()` is a no-op until it
		lands (row_actions' redteam item 1, mirrored by the three standalone cases
		in "RowActions final fix wave (redteam item 1, BLOCKER)"). Hosted mode
		matters here because it has THREE close callers the composite does not —
		the shared dispatcher's press-on-another-row, the coordinator shim over
		`scrollTop`, and the list's own `outsideDismiss` — and each one reaches the
		engine by a different route. A route that cancelled a commit would eat a
		delete the player already committed to. ]]
	local function commitInFlight(w: any, key: string): number
		local rect = w.adapter.node(rowHit(key)).rect
		w.dragLeft(key, rect.w * 0.75)
		w.release()
		-- run a few frames: far enough that the slide-off has started, early
		-- enough that the action has NOT fired yet — the window under test
		for _ = 1, 6 do
			w.tick(FRAME)
		end
		return rect.w
	end

	it("(P4) a sibling row starting a gesture during a commit: the commit still fires exactly once", function()
		local fired: { string } = {}
		local w = world({ rowActions = destructiveActions(fired) })
		local rowWidth = commitInFlight(w, "r2")
		expect(fired).toEqual({}) -- mid-flight, before the fire
		expect(w.list.engagedOffset:get() < -rowWidth * 0.6).toBe(true)
		-- r4 presses: the dispatcher asks r2's engine to close (the in-list
		-- dismiss) AND the coordinator claim moves — neither may cancel r2
		w.dragLeft("r4", 80)
		expect(fired).toEqual({})
		w.release()
		w.settle(400)
		expect(fired).toEqual({ "r2" }) -- completed, exactly once
		expect(w.adapter.node(rowPath("r2")).rect.h).toBe(40) -- and recovered
	end)

	it("(P5) a scroll during a commit: the commit still fires exactly once", function()
		local fired: { string } = {}
		local w = world({ rowActions = destructiveActions(fired) })
		commitInFlight(w, "r2")
		expect(fired).toEqual({})
		-- the coordinator's own scroll-close (case (e)'s mechanism) arrives
		-- mid-commit
		w.adapter.driveScroll("/S/VL", { x = 0, y = 25 })
		w.pres.refresh()
		expect(fired).toEqual({})
		w.settle(400)
		expect(fired).toEqual({ "r2" })
		expect(w.debug().engagedKey).toBeNil()
	end)

	it("(P6) an outside tap during a commit: the commit fires once and the tapped control still activates", function()
		local fired: { string } = {}
		local w = world({ rowActions = destructiveActions(fired), sibling = true })
		commitInFlight(w, "r2")
		expect(fired).toEqual({})
		-- the list's own `outsideDismiss.dismiss` (== the engaged engine's close)
		-- fires here, and must be a no-op while committing — while the round-7
		-- no-swallow rule still delivers the tap
		w.adapter.tap("/S/Outside")
		w.pres.refresh()
		expect(fired).toEqual({})
		expect(w.activations).toEqual({ "outside" })
		w.settle(400)
		expect(fired).toEqual({ "r2" })
	end)

	it("(P7) one open at a time: a SETTLED open row closes when another row settles open", function()
		--[[ (b2)/(x) prove the handoff while the second gesture is still LIVE. The
			settled pair is the state a player actually leaves the list in, and it
			is the one that can strand a tray: both rows have engines, both have
			been released, and only one may be open. ]]
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		local travel = expectedTravel(w, trayAction("r2", "trailing", "delete"), "Delete")
		expect(w.list.engagedOffset:get()).toBe(-travel)

		w.dragLeft("r4", 80)
		w.release()
		w.settle()
		expect(w.debug().engagedKey).toBe("r4")
		expect(w.debug().engineCount).toBe(2) -- both rows kept their engines...
		expect(w.list.engagedOffset:get()).toBe(-travel)
		-- ...and r2 is closed: no tray, no slide, and its own content is flat
		expect(w.adapter.node(trayGroup("r2"))).toBeNil()
		expect(w.adapter.node(rowPath("r2")).presentationOffset.x).toBe(0)
		expect(w.adapter.node(trayGroup("r4"))).never().toBeNil()
		-- and back again: r2 re-opens, r4 closes — the policy holds both ways
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		expect(w.debug().engagedKey).toBe("r2")
		expect(w.adapter.node(trayGroup("r4"))).toBeNil()
		expect(#fired).toBe(0) -- nothing fired through any of it
	end)

	it("(P8) keyboard Delete on the focused row hit fires its first destructive action", function()
		--[[ The standalone mirror is "Delete on a focused row fires the first
			destructive action" (Task 8). The engine binds that key context itself,
			scoped to focus being inside the row — and `pathInsideRow` already
			accepts the host's tray paths (Task 2, finding 2). What hosted mode adds
			is the RELAY: a node-less engine can only be handed the action system and
			the focus graph by the LIST's contribution, and only ever at build. If
			either handoff were dropped, this key would be dead. ]]
		local fired: { string } = {}
		local w = world({ rowActions = destructiveActions(fired) })
		-- the row's engine exists (see (P8b) for why that is a precondition):
		-- swipe r1 and put it away again
		w.dragLeft("r1", 80)
		w.release()
		w.settle()
		w.close()
		expect(w.debug().engagedKey).toBeNil()
		-- focus sits on the first row's hit (the presenter's own initial focus)
		expect(w.pres.focus.focused:get()).toBe(rowHit("r1"))
		w.system.deviceKey("Delete", true)
		w.system.deviceKey("Delete", false)
		w.settle(400)
		expect(fired).toEqual({ "r1" })
		expect(w.activations).toEqual({}) -- Delete is not an activate
		-- and it does not fire twice for one press
		w.settle(200)
		expect(fired).toEqual({ "r1" })
	end)

	--[[ ===== THE UNSWIPED ROW'S KEY SURFACE (parity round 3, owed row 9) ======
		(P8b) used to pin the GAP: the Delete context belongs to the ENGINE, and a
		hosted engine is built by the first pointer gesture that resolves
		horizontal, so a row a keyboard-only or pad-only player had merely focused
		had no engine and therefore no binding at all — not Delete, and not the
		action menu either, which is how a pad reaches a NON-destructive action.
		Row actions were reachable by pointer only, which the cross-platform rule
		forbids.

		THE LIST HOLDS THE ROW'S KEY SURFACE NOW, standing in for the engine that
		does not exist yet: one context per list, enabled only while the ring is on
		a row hit whose row declares actions, binding exactly the keys row_actions
		itself binds (`row_actions.ROW_KEYS`, one declaration both sides read), and
		BUILDING that one row's engine on the press. One engine per press that
		needs one — never one per row a d-pad passes over, which is what the
		laziness the hosted design exists for would have cost. ]]
	it("(P8b) Delete on a row NOBODY has swiped fires its destructive action, building ONE engine", function()
		local fired: { string } = {}
		local w = world({ rowActions = destructiveActions(fired) })
		expect(w.pres.focus.focused:get()).toBe(rowHit("r1"))
		expect(w.debug().engineCount).toBe(0) -- nothing built by mounting or focusing
		w.system.deviceKey("Delete", true)
		w.system.deviceKey("Delete", false)
		w.settle(400)
		expect(fired).toEqual({ "r1" })
		expect(w.activations).toEqual({}) -- Delete is not an activate
		expect(w.debug().engineCount).toBe(1) -- exactly the row the key was pressed on
		-- and one press is one commit
		w.settle(200)
		expect(fired).toEqual({ "r1" })
	end)

	it(
		"(P8c) ButtonX on an unswiped row opens its action MENU — the pad's route to a non-destructive action",
		function()
			local fired: { string } = {}
			local w = world({ rowActions = bothEdges(fired) })
			local function menuNodes(): number
				local n = 0
				for _, path in w.adapter.paths() do
					if string.find(path, "RowActionsMenu", 1, true) ~= nil then
						n += 1
					end
				end
				return n
			end
			expect(w.debug().engineCount).toBe(0)
			w.system.deviceKey("ButtonX", true)
			w.system.deviceKey("ButtonX", false)
			w.settle(60)
			expect(menuNodes() > 0).toBe(true)
			expect(w.debug().engineCount).toBe(1)
			expect(w.debug().engagedKey).toBeNil() -- a menu is not a revealed tray
		end
	)

	it("(P8d) a d-pad WALK builds nothing: the press is what materialises an engine", function()
		--[[ The laziness guarantee, re-proved against the new binding. The context
			is enabled by focus, but nothing is CONSTRUCTED by focus — a player who
			walks the whole window and presses nothing must leave the list exactly
			as cheap as they found it. ]]
		local fired: { string } = {}
		local w = world({ rowActions = destructiveActions(fired) })
		for _ = 1, 8 do
			w.system.deviceKey("DPadDown", true)
			w.system.deviceKey("DPadDown", false)
		end
		w.settle(30)
		expect(w.pres.focus.focused:get()).toBe(rowHit("r9"))
		expect(w.debug().engineCount).toBe(0)
		w.system.deviceKey("Delete", true)
		w.system.deviceKey("Delete", false)
		w.settle(400)
		expect(fired).toEqual({ "r9" }) -- the row the RING was on, not the first row
		expect(w.debug().engineCount).toBe(1)
	end)

	it("(P8e) a row that declares NO actions is untouched: Delete builds nothing and fires nothing", function()
		local fired: { string } = {}
		local w = world({
			rowActions = function(item: any): any
				if item.id == "r1" then
					return nil -- this row has no actions at all
				end
				return destructiveActions(fired)(item)
			end,
		})
		expect(w.pres.focus.focused:get()).toBe(rowHit("r1"))
		w.system.deviceKey("Delete", true)
		w.system.deviceKey("Delete", false)
		w.settle(200)
		expect(fired).toEqual({})
		expect(w.debug().engineCount).toBe(0)
		-- the row below it, which does declare actions, still answers
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		w.system.deviceKey("Delete", true)
		w.system.deviceKey("Delete", false)
		w.settle(400)
		expect(fired).toEqual({ "r2" })
	end)

	it("(P8g) BOTH spellings of both verbs reach an unswiped row (the one shared key table)", function()
		--[[ `row_actions.ROW_KEYS` is read twice — by the engine's own context and
			by the list's stand-in — so that a host cannot ship half the vocabulary.
			Delete/Backspace are one verb and ButtonX/Shift+Return are the other;
			the primary spelling of each is proved in (P8b)/(P8c), and these are the
			ones a host that hand-listed its bindings would have dropped. ]]
		local fired: { string } = {}
		local w = world({ rowActions = destructiveActions(fired) })
		w.system.deviceKey("Backspace", true)
		w.system.deviceKey("Backspace", false)
		w.settle(400)
		expect(fired).toEqual({ "r1" })

		local menu = world({ rowActions = bothEdges({}) })
		menu.system.deviceKey("LeftShift", true)
		menu.system.deviceKey("Return", true)
		menu.system.deviceKey("Return", false)
		menu.system.deviceKey("LeftShift", false)
		menu.settle(60)
		local menuNodes = 0
		for _, path in menu.adapter.paths() do
			if string.find(path, "RowActionsMenu", 1, true) ~= nil then
				menuNodes += 1
			end
		end
		expect(menuNodes > 0).toBe(true)
		expect(menu.activations).toEqual({}) -- and plain Return's Activate never ran
	end)

	it("(P8h) the list owns Delete only while the ring is on an ACTIONABLE row", function()
		--[[ The stand-in sinks, so what it is enabled for decides what else on the
			screen can still see the key. Enablement is scoped to "the ring is on a
			row hit of this list, and that row declares actions" — a row with no
			actions leaves Delete to whoever else wants it, which is the difference
			between owning a key and squatting on it. ]]
		local fired: { string } = {}
		local w = world({
			rowActions = function(item: any): any
				if item.id == "r1" then
					return nil
				end
				return destructiveActions(fired)(item)
			end,
		})
		-- a sibling that also wants Delete, at an ordinary priority
		local seen = 0
		local ctx = w.system.createContext({ name = "SiblingDelete", priority = 1000 })
		local action = ctx.createAction("SiblingDelete", "Bool")
		action.bind({ keyCode = "Delete" })
		action.onPressed(function()
			seen += 1
		end)
		-- the ring starts on r1, which declares NO actions: the sibling gets it
		w.system.deviceKey("Delete", true)
		w.system.deviceKey("Delete", false)
		w.settle(30)
		expect(seen).toBe(1)
		expect(fired).toEqual({})
		-- ...and on r2, which does declare actions, the row owns the key
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		w.system.deviceKey("Delete", true)
		w.system.deviceKey("Delete", false)
		w.settle(400)
		expect(seen).toBe(1) -- sunk, not delivered twice
		expect(fired).toEqual({ "r2" })
	end)

	it("(P8f) once the engine EXISTS it is the one that answers: Delete still fires exactly once", function()
		--[[ Two bindings now name Delete on the same row — the engine's own
			(priority 10000, sink) and the list's stand-in. The engine's sink is
			what keeps them from both firing; this is the case that would catch a
			double commit if the two ever ended up at the same priority. ]]
		local fired: { string } = {}
		local w = world({ rowActions = destructiveActions(fired) })
		w.dragLeft("r1", 80) -- build the engine the pointer way, then put it away
		w.release()
		w.settle()
		w.close()
		expect(w.debug().engineCount).toBe(1)
		expect(w.pres.focus.focused:get()).toBe(rowHit("r1"))
		w.system.deviceKey("Delete", true)
		w.system.deviceKey("Delete", false)
		w.settle(400)
		expect(fired).toEqual({ "r1" }) -- ONE fire, not two
		expect(w.debug().engineCount).toBe(1)
	end)

	-- press a device key (down + up), the shape every case here drives focus with
	local function press(w: any, key: string)
		w.system.deviceKey(key, true)
		w.system.deviceKey(key, false)
	end

	it("(P9) focus TRAVERSAL: the d-pad reaches the revealed tray, and the ring comes BACK to the row", function()
		--[[ THE FIX (Task 4 carried item 1, reshaped by fix round 1 R1/R2). A
			contribution OWNS its subtree's focus — `focus_map.autoGroups` emits this
			control's groups and does not descend — so a focusable the list never
			names is unreachable by every non-pointer input there is. The tray
			buttons under the shared overlay were exactly that: a player could swipe
			a row open with a finger and then have no way to press the action they
			had just revealed.

			The revealed tray is now its OWN horizontal group (R2 — a strip of
			buttons spliced into the vertical row group made Left/Right dead and Down
			walk visually rightward), entered from the row by pressing toward the
			edge the tray is on, and left the way it was entered — landing back on
			the ENGAGED row, not on the top of the window. ]]
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		local action = trayAction("r2", "trailing", "delete")
		-- CLOSED: ONE group, row hits and nothing else
		local closed = w.handle.focusOrder().navigation
		expect(#closed).toBe(1)
		for _, entry in closed[1].order do
			expect(string.find(tostring(entry), "RowActionsOverlay", 1, true)).toBeNil()
		end

		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		--[[ OPEN: TWO groups. The row group is untouched (still only row hits) and
			gains ONE exit — `right`, because a trailing tray is revealed at the
			row's right edge; the tray group is horizontal, contained, and exits back
			left into the rows. ]]
		local groups = w.handle.focusOrder().navigation
		expect(#groups).toBe(2)
		for _, entry in groups[1].order do
			expect(string.find(tostring(entry), "RowActionsOverlay", 1, true)).toBeNil()
		end
		expect(groups[1].axis).toBe("vertical")
		expect(groups[2].axis).toBe("horizontal") -- a strip of buttons, not a column
		expect(groups[2].order).toEqual({ action })
		-- (the dump carries name/axis/order only, so the exit map, the containment
		-- and the restore entry are proven where they are felt — by driving the
		-- pad, below and in (P9c)/(P9d))

		-- ...and the d-pad walks it: r1 (initial focus) -> r2 -> right, into the tray
		expect(w.pres.focus.focused:get()).toBe(rowHit("r1"))
		press(w, "DPadDown")
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
		press(w, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe(action)
		expect(w.adapter.node(action).focused).toBe(true) -- and the ring is painted
		-- ...back out the way it came in: onto the ENGAGED row, not row 1
		press(w, "DPadLeft")
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))

		-- ButtonA on the action fires it, exactly as a tap does — and closes the row
		press(w, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe(action)
		press(w, "ButtonA")
		w.settle()
		expect(fired).toEqual({ "r2" })
		expect(w.activations).toEqual({}) -- never the row's own activate
		expect(w.debug().engagedKey).toBeNil()
		--[[ R1: THE RING SURVIVES THE TRAY IT WAS ON. The button it sat on has
			unmounted, and the graph's own answer for a vanished focus in a grouped
			scope is `entryFocus` — the first focusable in the whole scope, i.e. r1
			(on a real screen, whatever sits at the top). It must be the row the
			player was working on. ]]
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
		expect(w.adapter.node(rowHit("r2")).focused).toBe(true)
		-- the tray is gone, so the map is one group again
		expect(#w.handle.focusOrder().navigation).toBe(1)
	end)

	it("(P9a) R1: EVERY close returns the ring to the row — scroll, Cancel and an outside tap too", function()
		--[[ The tray-button Activate above is the close a player takes on purpose.
			These are the ones that happen TO them while the ring sits on a tray
			button, and each reaches the engagement through a different seam — so
			each is its own chance to strand the ring at the top of the surface. ]]
		local fired: { string } = {}
		local function toTray(w: any)
			w.dragLeft("r2", 80)
			w.release()
			w.settle()
			press(w, "DPadDown")
			press(w, "DPadRight")
			expect(w.pres.focus.focused:get()).toBe(trayAction("r2", "trailing", "delete"))
		end

		-- (1) a SCROLL (the coordinator's own close)
		local scrolled = world({ rowActions = trailingActions(fired) })
		toTray(scrolled)
		scrolled.close()
		expect(scrolled.pres.focus.focused:get()).toBe(rowHit("r2"))

		-- (2) CANCEL / ButtonB (the list's handleCancel -> the engine)
		local cancelled = world({ rowActions = trailingActions(fired) })
		toTray(cancelled)
		press(cancelled, "ButtonB")
		cancelled.settle()
		expect(cancelled.debug().engagedKey).toBeNil()
		expect(cancelled.pres.focus.focused:get()).toBe(rowHit("r2"))

		-- (3) a tap OUTSIDE the list (the presenter's outsideDismiss)
		local tapped = world({ rowActions = trailingActions(fired), sibling = true })
		toTray(tapped)
		tapped.adapter.tap("/S/Outside")
		tapped.settle()
		expect(tapped.debug().engagedKey).toBeNil()
		-- ...and here the ring follows the TAP, which is the right answer and the
		-- reason this case is worth having: the restore must not fight a focus move
		-- the player just made themselves, and it does not — what it prevents is
		-- the ring being stranded at the top of the surface, which is neither of
		-- these two paths
		expect(tapped.pres.focus.focused:get()).toBe("/S/Outside")
		expect(#fired).toBe(0) -- none of these is a commit
	end)

	it("(P9c) a MULTI-ACTION tray navigates HORIZONTALLY, and is contained", function()
		--[[ R2's own case, and the one every other case in this file was blind to:
			a ONE-action tray cannot tell a horizontal group from a vertical one.
			With two actions the difference is the whole feature — Left/Right step
			between them, and the vertical presses that used to walk the row group
			(landing on the NEXT ROW while the ring appeared to move sideways) do
			nothing at all inside a contained strip. ]]
		local fired: { string } = {}
		local w = world({
			rowActions = function(item: any): any
				return {
					trailing = {
						{
							id = "flag",
							label = "Flag",
							onAction = function()
								table.insert(fired, `flag:{item.id}`)
							end,
						},
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
		local flag = trayAction("r2", "trailing", "flag")
		local delete = trayAction("r2", "trailing", "delete")
		w.dragLeft("r2", 120)
		w.release()
		w.settle()
		local groups = w.handle.focusOrder().navigation
		expect(groups[2].order).toEqual({ flag, delete }) -- document order, left to right

		press(w, "DPadDown")
		press(w, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe(flag) -- the near end: entered from the row
		press(w, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe(delete)
		-- CONTAINED: no exit past the far end, and none along the other axis —
		-- the row group is one press away, but only through the way in
		press(w, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe(delete)
		press(w, "DPadDown")
		expect(w.pres.focus.focused:get()).toBe(delete)
		press(w, "DPadUp")
		expect(w.pres.focus.focused:get()).toBe(delete)
		-- ...and back out, one step at a time, onto the row it belongs to
		press(w, "DPadLeft")
		expect(w.pres.focus.focused:get()).toBe(flag)
		press(w, "DPadLeft")
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
		-- the SECOND action is reachable and fires alone
		press(w, "DPadRight")
		press(w, "DPadRight")
		press(w, "ButtonA")
		w.settle()
		expect(fired).toEqual({ "r2" }) -- Delete, not Flag
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
	end)

	it("(P9d) a LEADING tray is entered from the other side (the edge decides the direction)", function()
		local fired: { string } = {}
		local w = world({
			rowActions = function(item: any): any
				return {
					leading = {
						{
							id = "flag",
							label = "Flag",
							onAction = function()
								table.insert(fired, `flag:{item.id}`)
							end,
						},
					},
				}
			end,
		})
		local flag = trayAction("r2", "leading", "flag")
		w.dragRight("r2", 60)
		w.release()
		w.settle()
		--[[ a leading tray sits at the row's LEFT edge, so LEFT is what enters it
			and RIGHT is what comes back — the mirror of the trailing case. It also
			sits BEFORE the row group in the array, which is what keeps the
			UNdeclared directions honest: an uncontained group falls through the
			group array in order, so with the tray pinned last a Right press reached
			a LEADING tray for want of anywhere else to fall through to. ]]
		local groups = w.handle.focusOrder().navigation
		expect(#groups).toBe(2)
		expect(groups[1].order).toEqual({ flag })
		expect(groups[2].order[1]).toBe(rowHit("r1"))
		press(w, "DPadDown")
		-- RIGHT does nothing: there is no trailing tray to enter (the row group's
		-- only tray exit is the edge the revealed tray is actually on)
		press(w, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
		press(w, "DPadLeft")
		expect(w.pres.focus.focused:get()).toBe(flag)
		press(w, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
	end)

	it("(P9b) Tab reaches the revealed tray button too (the presenter's document-order rank)", function()
		--[[ The d-pad walks the GROUP; Tab walks the presenter's RANK, which is
			document order (traversal-document-order, 2026-08-03). The overlay is a
			sibling of the rows region rather than a child of the row, so a hosted
			tray tabs AFTER the windowed rows rather than beside its own row — a
			structural consequence of hosting ONE shared overlay, named here so the
			difference from standalone is recorded rather than discovered. ]]
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired), keyboardNavigation = true })
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		local action = trayAction("r2", "trailing", "delete")
		local ranked = w.handle.focusOrder().traversal
		expect(ranked[#ranked].path).toBe(action) -- last in the reading order
		-- Tab all the way round: the button IS reached, and the ring lands on it
		local seen = false
		for _ = 1, #ranked do
			w.system.deviceKey("Tab", true)
			w.system.deviceKey("Tab", false)
			if w.pres.focus.focused:get() == action then
				seen = true
				break
			end
		end
		expect(seen).toBe(true)
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		w.settle()
		expect(fired).toEqual({ "r2" })
	end)

	it("(P10) the ACTIVATE SEAM closes the open row: Return on ANOTHER row puts the tray away", function()
		--[[ K1 (Task 4 re-review). The pointer half of the in-list dismiss lives in
			the shared dispatcher, on the DOWN — and a keyboard Return or a gamepad
			ButtonA produces no pointer event at all. The presenter's own
			outside-dismiss cannot cover it either: every row is inside the ONE list
			contribution, so "another row" is never outside. The open tray simply
			stayed up while the player operated a different row — hosted-only,
			because standalone and Table rows are per-row contributions. ]]
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		-- r5 is open (by finger), and focus is still on r1 where it started
		w.dragLeft("r5", 80)
		w.release()
		w.settle()
		expect(w.debug().engagedKey).toBe("r5")
		expect(w.pres.focus.focused:get()).toBe(rowHit("r1"))
		w.system.deviceKey("Return", true)
		w.system.deviceKey("Return", false)
		w.settle()
		expect(w.debug().engagedKey).toBeNil()
		expect(w.adapter.node(trayGroup("r5"))).toBeNil()
		expect(w.adapter.node(rowPath("r5")).presentationOffset.x).toBe(0)
		-- ...and the Activate was NOT swallowed: r1 still activated (round 7's
		-- rule, the same one `consume = false` carries at the pointer seam)
		expect(w.activations).toEqual({ "r1" })
		expect(#fired).toBe(0)
	end)

	it("(P12) X1: an AUTHOR'S OWN exit does not lock the player out of a revealed tray", function()
		--[[ THE REGRESSION THIS ROUND FIXED. The tray's group is CONTAINED, so the
			exit the row group declares toward it is the ONLY way a d-pad gets in —
			and the first draft merged that exit non-destructively (`merged.right =
			merged.right or trayGroup`). A list that declares `navigation.exit.right`
			(an ordinary thing: "Right leaves this list for the detail panel") would
			therefore have had a revealed tray that no non-pointer input could reach
			at all.

			THE RULE NOW: while a tray is up it wins the one direction that reaches
			it, exactly as a modal trumps ambient navigation — and the author's exit
			is not overwritten anywhere, it is rebuilt from the spec every refresh,
			so it is back the frame the tray closes. Both halves are asserted here,
			against a REAL neighbouring group (the sibling button's own auto group)
			rather than a name that resolves to nothing. ]]
		local fired: { string } = {}
		local w = world({
			rowActions = trailingActions(fired),
			sibling = true,
			navigation = { exit = { right = "auto-flat-1" } },
		})
		-- the neighbour really is there, under the name the author declared
		local names: { string } = {}
		for _, group in w.handle.focusOrder().navigation do
			table.insert(names, group.name)
		end
		expect(table.find(names, "auto-flat-1") ~= nil).toBe(true)

		-- CLOSED: the author's exit is what Right means
		press(w, "DPadDown")
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
		press(w, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe("/S/Outside")

		-- ...a tray is revealed, and now Right reaches the ACTIONS
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		-- (the swipe was a pointer gesture, which leaves the ring where it was)
		w.pres.focus.focusOn(rowHit("r2"))
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
		press(w, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe(trayAction("r2", "trailing", "delete"))
		-- ...and back out the way it came in
		press(w, "DPadLeft")
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))

		-- ...the tray closes, and the author's exit is back — not overwritten
		w.close()
		expect(w.debug().engagedKey).toBeNil()
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
		press(w, "DPadRight")
		expect(w.pres.focus.focused:get()).toBe("/S/Outside")
		expect(#fired).toBe(0)
	end)

	it("(P13) X2: with EVERY row focus-skipped, the revealed tray is still reachable", function()
		--[[ `rowFocusable` is a live predicate (SF-L3), and a list may legitimately
			answer false for every row it currently holds — at which point the row
			group is all-ineligible and the graph treats it as transparent rather
			than as a wall. The question this round asked is what that does to a
			revealed tray, whose group is reached BY an exit from those very rows.

			The answer is that the tray stays reachable, because Tab walks the
			presenter's rank over the whole scope rather than the exits: the tray
			button is the only eligible stop on the surface, and it is where the ring
			lands. (The d-pad's own way in is gone with the rows it started from —
			there is nothing focusable to press Right FROM — which is a property of
			the author's predicate, not of the tray.) ]]
		local fired: { string } = {}
		local w = world({
			rowActions = trailingActions(fired),
			rowFocusable = function(): boolean
				return false
			end,
			keyboardNavigation = true,
		})
		-- nothing in the list takes focus at all while it is closed
		expect(w.pres.focus.focused:get()).toBeNil()
		expect(#w.handle.focusOrder().navigation).toBe(1)

		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		local action = trayAction("r2", "trailing", "delete")
		press(w, "Tab")
		expect(w.pres.focus.focused:get()).toBe(action)
		press(w, "Return")
		w.settle()
		expect(fired).toEqual({ "r2" })
		-- ...and the map is back to the one (all-ineligible) row group afterwards
		expect(w.debug().engagedKey).toBeNil()
		expect(#w.handle.focusOrder().navigation).toBe(1)
	end)

	it("(P11) closing another row takes its action MENU with it, not just its tray", function()
		--[[ A row's action menu (ButtonX) is INDEPENDENT state from its tray
			(`row_actions.luau`'s own `menuOpen`), which is why the coordinator's
			claim calls `_closeMenu()` alongside `_close()` on the row it claims away
			from (redteam item 7). But a claim only happens when a gesture crosses
			the axis lock, and this control's own close seams are not gestures: a TAP
			on another row claims nothing at all. Closing only the tray there would
			strand the menu — and its `transientScope` focus trap — over a row the
			player had already moved on from.

			BOTH SEAMS (the pointer dispatcher and Activate) go through the one
			`hostedCloseRow`, so they cannot diverge. Only the pointer one is
			REACHABLE with a menu up, and that is not an accident: while the menu is
			open it traps focus, so a keyboard Activate can only ever be dispatched
			to a node inside the menu itself. ]]
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		local function menuNodes(): number
			local n = 0
			for _, path in w.adapter.paths() do
				if string.find(path, "RowActionsMenu", 1, true) ~= nil then
					n += 1
				end
			end
			return n
		end
		w.dragLeft("r2", 80)
		w.release()
		w.settle()
		w.system.deviceKey("DPadDown", true)
		w.system.deviceKey("DPadDown", false)
		expect(w.pres.focus.focused:get()).toBe(rowHit("r2"))
		w.system.deviceKey("ButtonX", true)
		w.system.deviceKey("ButtonX", false)
		w.pres.refresh()
		expect(menuNodes() > 0).toBe(true) -- tray AND menu are up on r2
		expect(w.debug().engagedKey).toBe("r2")

		-- a plain TAP on another row: no gesture, so nothing claims the coordinator
		w.adapter.touchTap(rowHit("r5"))
		w.settle()
		expect(menuNodes()).toBe(0) -- the menu went with the tray
		expect(w.debug().engagedKey).toBeNil()
		expect(w.adapter.node(trayGroup("r2"))).toBeNil()
		-- HEADLESS ARTIFACT, not a device promise: `fake_target.touchTap` fires
		-- onActivate unconditionally after down/up, but a real tap here would land
		-- on the still-modal menu (`outsideTapCancel = true`,
		-- src/controls/row_actions.luau:1761-1766), whose `applyOutsideOutcome` would
		-- dismiss it and CONSUME the tap -- r5 would not activate on a real device.
		-- The case's real claim (the menu goes with the tray) is proven above and is
		-- mutation-bitten; only this activation count rides the harness's
		-- unconditional tap.
		expect(w.activations).toEqual({ "r5" }) -- and the press was not swallowed
		expect(#fired).toBe(0)
	end)

	it("(P10b) R3: a NON-POINTER Activate on the OPEN row's own hit closes it, exactly as a tap does", function()
		--[[ THE DEVICE SPLIT (fix round 1, R3). A tap on the open row means "put it
			away, and only that" — the pointer seam says so on the UP, through
			`suppressActivatePath` (case (v3)). That mechanism is armed by
			`onPointerUp` and NOTHING else, so a keyboard Return or a gamepad ButtonA
			on the very same row used to activate it AND leave the tray standing:
			one row, one verb, two answers depending on which device the player
			happened to be holding.

			`meta.source == "action"` is how this control already tells a non-pointer
			Activate from a tap, and it is what decides it here. ]]
		local fired: { string } = {}
		local w = world({ rowActions = trailingActions(fired) })
		w.dragLeft("r1", 80)
		w.release()
		w.settle()
		expect(w.debug().engagedKey).toBe("r1")
		expect(w.pres.focus.focused:get()).toBe(rowHit("r1"))
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		w.settle()
		-- closed, and the press was SWALLOWED — the same verdict the tap gets
		expect(w.debug().engagedKey).toBeNil()
		expect(w.list.engagedOffset:get()).toBe(0)
		expect(w.adapter.node(trayGroup("r1"))).toBeNil()
		expect(w.adapter.node(rowPath("r1")).presentationOffset.x).toBe(0)
		expect(w.activations).toEqual({})
		expect(#fired).toBe(0)
		-- ...and the row is an ordinary row again: the NEXT one activates, exactly
		-- as (v3) proves for the tap
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		expect(w.activations).toEqual({ "r1" })
	end)
end)

-- =============================================================================
--[[ THE RELEASE ACTIVATE, ON THE HOSTED SURFACE (redteam NEW-1, BLOCKER;
	2026-08-13) ─────────────────────────────────────────────────────────────────
	A hosted row's `Hit` is a real engine `GuiButton`. The same pointer sequence
	that swipes it therefore ends in that button's own `Activated` — "whichever
	side of `InputEnded` it lands", the fact `virtual_list.luau`'s
	`suppressActivatePath` declaration has recorded since Task 3. The arm for it
	existed in exactly ONE place: `hostedDispatch.onPointerUp`'s `unresolved`
	branch, i.e. a TAP on an already-open row. A gesture that resolved HORIZONTAL
	— every real swipe — armed nothing at all, so `handleActivate` fell past the
	`engaged == key` test (which answers only `meta.source == "action"`), past the
	`suppressActivatePath == path` test, and into `spec.onActivate`.

	Table's twin was order-dependent. This one was not: measured RED on BOTH
	orders, BOTH edges and BOTH pointer kinds — 8 of these 12 combinations. On the
	shipped playlist analogue that reads "swipe to reveal Remove, and the track
	plays".

	WHY 2000 LINES OF HOSTED SPECS DID NOT SEE IT: every swipe in this file ended
	at `w.release()`, a SILENT up. That is a real release — an up landing off the
	translated hit produces one — but it is not the common one, and the four
	silent rows below are the CONTROL, not the coverage. The other eight drive
	`w.releaseActivating(order)`, which delivers the engine's own `Activated` with
	the full pointer meta.

	Each case asserts the two things that have to be simultaneously true and were
	not: the tray is revealed and stays revealed, and `onActivate` did not fire.
	`fired` is checked too — a swipe must not run an ACTION either. ]]
describe("VirtualList rowActions (redteam NEW-1): a hosted swipe survives its own release Activate", function()
	--[[ ONE swipe, on the hosted surface, released the way the case names.
		`edge` picks the direction and therefore which tray must appear. Returns
		nothing: every verdict is read off the world afterwards, from the mounted
		tree and the recorded callbacks. ]]
	local function swipe(w: any, key: string, edge: string, pointerType: string, order: ("before" | "after")?)
		if edge == "leading" then
			w.dragRight(key, 80, pointerType)
		else
			w.dragLeft(key, 80, pointerType)
		end
		if order == nil then
			w.release()
		else
			w.releaseActivating(order)
		end
		w.settle()
	end

	--[[ The twelve titles are written out in full rather than interpolated, for
		the same reason `row_actions_scenario.spec.luau`'s own four are: a check
		that greps for a case name cannot find a title assembled at runtime. ]]
	local RELEASE_CASES = {
		{
			pointerType = "touch",
			order = nil :: ("before" | "after")?,
			title = "RowActions hosted touch: a VirtualList swipe reveals the tray and fires no onActivate (silent release, control)",
		},
		{
			pointerType = "touch",
			order = "after" :: ("before" | "after")?,
			title = "RowActions hosted touch: a VirtualList swipe reveals the tray and survives its release Activate (after)",
		},
		{
			pointerType = "touch",
			order = "before" :: ("before" | "after")?,
			title = "RowActions hosted touch: a VirtualList swipe reveals the tray and survives its release Activate (before)",
		},
		{
			pointerType = "mouse",
			order = nil :: ("before" | "after")?,
			title = "RowActions hosted mouse: a VirtualList swipe reveals the tray and fires no onActivate (silent release, control)",
		},
		{
			pointerType = "mouse",
			order = "after" :: ("before" | "after")?,
			title = "RowActions hosted mouse: a VirtualList swipe reveals the tray and survives its release Activate (after)",
		},
		{
			pointerType = "mouse",
			order = "before" :: ("before" | "after")?,
			title = "RowActions hosted mouse: a VirtualList swipe reveals the tray and survives its release Activate (before)",
		},
	}
	for _, case in RELEASE_CASES do
		local pointerType, order = case.pointerType, case.order
		it(case.title, function()
			-- TRAILING (Apple's default edge)
			local fired: { string } = {}
			local w = world({ rowActions = bothEdges(fired) })
			expect(w.debug().engagedKey).toBeNil()
			expect(w.adapter.node(tray("r2", "trailing"))).toBeNil()

			swipe(w, "r2", "trailing", pointerType, order)
			expect(w.adapter.node(trayAction("r2", "trailing", "delete"))).never().toBeNil()
			expect(w.debug().engagedKey).toBe("r2") -- revealed, and STILL revealed
			expect(w.list.engagedOffset:get() < 0).toBe(true)
			expect(w.activations).toEqual({}) -- a swipe is not a tap
			expect(fired).toEqual({}) -- and it ran no action either
			expect(#w.handle.controller.diagnostics()).toBe(0)

			-- LEADING — the other edge, on a FRESH world. Swiping the other way
			-- out of an already-open tray is the CLOSE gesture, which would have
			-- passed this case for entirely the wrong reason.
			local leadFired: { string } = {}
			local lead = world({ rowActions = bothEdges(leadFired) })
			expect(lead.adapter.node(tray("r2", "leading"))).toBeNil()

			swipe(lead, "r2", "leading", pointerType, order)
			expect(lead.adapter.node(trayAction("r2", "leading", "flag"))).never().toBeNil()
			expect(lead.debug().engagedKey).toBe("r2")
			expect(lead.list.engagedOffset:get() > 0).toBe(true)
			expect(lead.activations).toEqual({})
			expect(leadFired).toEqual({})
			expect(#lead.handle.controller.diagnostics()).toBe(0)
		end)
	end

	--[[ THE SUPPRESSION IS ONE POINTER ACTIVATE WIDE, and a DEVICE Activate is
		never it (redteam NEW-2's rule, on this control). The arm is spent by the
		artifact it was raised for; the very next tap on the row is genuine. ]]
	it("the arm is one activate wide: the tap AFTER a swipe's release Activate still closes the tray", function()
		local fired: { string } = {}
		local w = world({ rowActions = bothEdges(fired) })
		w.dragLeft("r2", 80, "touch")
		w.releaseActivating("after")
		w.settle()
		expect(w.debug().engagedKey).toBe("r2")
		expect(w.activations).toEqual({})
		-- the next tap on the open row means CLOSE, exactly as it does with no
		-- release Activate in the story at all
		w.adapter.touchTap(rowHit("r2"))
		w.settle()
		expect(w.debug().engagedKey).toBeNil()
		expect(w.activations).toEqual({})
		-- ...and the one after THAT is an ordinary activate
		w.adapter.touchTap(rowHit("r2"))
		w.settle()
		expect(w.activations).toEqual({ "r2" })
	end)

	--[[ A SWIPE THAT ENDS WITH NO ACTIVATED AT ALL MUST NOT EAT THE NEXT DEVICE
		PRESS (redteam NEW-2, on this control) ──────────────────────────────────
		Arming at the axis lock is right, but an arm has to be cleared by
		something. `a6229e0` justified clearing it only at the next pointer-DOWN,
		on a premise that is false: "a real Activated always fires between a
		pointer-up and the next pointer-down". TWO producers carry no pointer-down
		— an IAS device Activate, and the minimum-target hit expander's own
		`Activated` on a SEPARATE GuiButton. So a swipe whose release delivers
		nothing (a cancel, or an up landing off the translated hit) left the arm
		standing, and the next gamepad A on that row was swallowed whole. ]]
	it("a hosted swipe CANCELLED mid-gesture does not swallow the next gamepad Activate", function()
		local fired: { string } = {}
		local w = world({ rowActions = bothEdges(fired) })
		w.dragLeft("r2", 80, "touch")
		-- the Roblox menu opens / the capture is taken away: NO Activated follows
		w.adapter.interruptCapture()
		w.settle()
		expect(w.activations).toEqual({})
		w.pres.focus.focusOn(rowHit("r2"))
		w.pres.refresh()
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		w.settle()
		expect(w.activations).toEqual({ "r2" }) -- the press LANDED
		expect(fired).toEqual({})
	end)

	--[[ THE OTHER PRODUCER WITH NO POINTER-DOWN: the minimum-target hit expander.
		A SEPARATE `GuiButton` overlapping a short row, whose press fires THIS
		row's activate handler with a full POINTER meta and no pointer event on
		the row's own `Hit` (screen_target.luau's `pointerActivateMeta`).
		`adapter.driveActivate` is that seam's headless mirror. Being a pointer
		Activate it is not covered by the `meta.source == "action"` half of the
		fix, so the CANCEL clear is the only thing between a cancelled swipe and a
		dead press — this is the case that proves that clear is load-bearing. ]]
	it("a hosted swipe CANCELLED mid-gesture does not swallow the hit expander's Activate either", function()
		local fired: { string } = {}
		local w = world({ rowActions = bothEdges(fired) })
		w.dragLeft("r2", 80, "touch")
		w.adapter.interruptCapture()
		w.settle()
		local rect = w.adapter.node(rowHit("r2")).rect
		w.adapter.driveActivate(rowHit("r2"), {
			source = "pointer",
			pointer = "touch",
			x = rect.x + rect.w / 2,
			y = rect.y - 2, -- the 44px overhang: outside the row, inside the target
		})
		w.settle()
		expect(w.activations).toEqual({ "r2" })
		expect(fired).toEqual({})
	end)

	it("a hosted swipe with a SILENT release still answers the next gamepad Activate with a close", function()
		local fired: { string } = {}
		local w = world({ rowActions = bothEdges(fired) })
		w.dragLeft("r2", 80, "touch")
		w.release() -- the up landed off the translated hit: no Activated at all
		w.settle()
		expect(w.debug().engagedKey).toBe("r2")
		w.pres.focus.focusOn(rowHit("r2"))
		w.pres.refresh()
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		w.settle()
		-- the device verb on an open row is CLOSE, and it was not eaten by a
		-- suppression left over from the swipe
		expect(w.debug().engagedKey).toBeNil()
		expect(w.activations).toEqual({})
		-- ...and the row is an ordinary row again on the very next press
		w.system.deviceKey("ButtonA", true)
		w.system.deviceKey("ButtonA", false)
		w.settle()
		expect(w.activations).toEqual({ "r2" })
	end)

	--[[ ===== CARRIED DEFECT 3: A VERTICAL PAN IS NOT A TAP ====================
		`docs/plans/table-hosted-row-actions-stage2.md` §"three open hosted-mode
		defects", item 3 — "a vertical pan begun on a row still fires that row's
		`onActivate`", recorded as pre-existing and awaiting a device answer.

		IT IS THE SAME DEFECT redteam NEW-1 fixed one branch over, and the fix is
		the same line in the branch that was missed. `hostedResolveAxis` arms
		`suppressActivatePath` when the axis resolves HORIZONTAL, because the row's
		`Hit` is a real `GuiButton` and the swipe's own release produces an
		`Activated` on it. A gesture that resolves VERTICAL is a scroll — the native
		ScrollingFrame owns it and this dispatcher goes inert — but the button is
		STILL under the finger, and a short pan that begins and ends inside the same
		row still delivers `Activated` on release. So panning a list to read it
		opened whatever the row opens.

		THE ARM CANNOT OVER-REACH, which is what made this safe to fix without
		waiting for a device: it is one path wide, and it is spent or cleared by
		every producer that could otherwise be swallowed — the one POINTER Activate
		it exists for, the next pointer-down, a cancel (a scroll that takes the
		capture away goes through `onPointerCancel`, which clears it), and a DEVICE
		Activate is never eligible at all (`meta.source == "action"`; the rule in
		`docs/lessons/an-arm-set-by-a-gesture-must-name-what-may-spend-it.md`). The
		three cases below pin exactly those escapes.

		A LIVE MEASUREMENT STILL BELONGS TO IT and is recorded in the mission report:
		`fake_target` models handler WIRING, not the engine's input sinking, so
		whether the real engine delivers `Activated` after a scroll-stealing pan is
		a live-engine claim. What the headless net proves is the direction of the
		fix and that nothing else was swallowed by it. ]]
	it("(defect 3) a vertical pan begun on a row does NOT fire that row's onActivate", function()
		local fired: { string } = {}
		local w = world({ rowActions = bothEdges(fired) })
		w.dragDown("r2", 60, "touch") -- a pan: resolves VERTICAL, native scroll owns it
		w.releaseActivating("after") -- ...and the button under the finger fires anyway
		w.settle()
		expect(w.activations).toEqual({}) -- reading a list is not tapping it
		expect(fired).toEqual({}) -- and it ran no action either
		expect(w.debug().engagedKey).toBeNil() -- a pan opens no tray
	end)

	it("(defect 3) ...on BOTH sides of InputEnded, and upward too", function()
		for _, order in { "before", "after" } do
			local fired: { string } = {}
			local w = world({ rowActions = bothEdges(fired) })
			w.dragDown("r2", 90, "touch")
			w.releaseActivating(order :: any)
			w.settle()
			expect(w.activations).toEqual({})
			expect(fired).toEqual({})
		end
		-- upward, i.e. a negative dy — the sign the axis test reads through
		-- `math.abs`, pinned so a one-sided fix cannot pass
		local upFired: { string } = {}
		local up = world({ rowActions = bothEdges(upFired) })
		up.dragDown("r3", -70, "touch")
		up.releaseActivating("after")
		up.settle()
		expect(up.activations).toEqual({})
	end)

	--[[ THE THREE ESCAPES, so the fix stays one pan wide. A pan that suppressed
		more than its own release Activate would be a worse defect than the one it
		replaced: a list nobody could ever tap after scrolling it. ]]
	it("(defect 3) the pan's arm is spent by its own release and nothing more", function()
		local fired: { string } = {}
		local w = world({ rowActions = bothEdges(fired) })
		w.dragDown("r2", 60, "touch")
		w.releaseActivating("after")
		w.settle()
		expect(w.activations).toEqual({})
		-- (1) the very next TAP on the panned row is genuine
		w.adapter.touchTap(rowHit("r2"))
		w.settle()
		expect(w.activations).toEqual({ "r2" })

		-- (2) a pan whose release delivers NO Activated at all (the capture went
		-- to the scroll) must not leave the arm standing over the next gamepad A
		local w2 = world({ rowActions = bothEdges({}) })
		w2.dragDown("r2", 60, "touch")
		w2.adapter.interruptCapture()
		w2.settle()
		w2.pres.focus.focusOn(rowHit("r2"))
		w2.pres.refresh()
		w2.system.deviceKey("ButtonA", true)
		w2.system.deviceKey("ButtonA", false)
		w2.settle()
		expect(w2.activations).toEqual({ "r2" })

		-- (3) a DEVICE Activate is never eligible to spend it: pan, then A,
		-- without any pointer release in between
		local w3 = world({ rowActions = bothEdges({}) })
		w3.dragDown("r2", 60, "touch")
		w3.release()
		w3.settle()
		w3.pres.focus.focusOn(rowHit("r2"))
		w3.pres.refresh()
		w3.system.deviceKey("ButtonA", true)
		w3.system.deviceKey("ButtonA", false)
		w3.settle()
		expect(w3.activations).toEqual({ "r2" })
	end)
end)
