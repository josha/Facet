--!strict
-- RowActions Task 5: the mouse gesture (axis lock, live drag, flick velocity,
-- full-swipe commit). Drives pointers headlessly through the REAL adapter
-- capture — `adapter.pointerDown/pointerMove/pointerUp` against the
-- `Content/Hit` grip (src/controls/row_actions.luau's own hit surface),
-- exactly the idiom tests/pointer.spec.luau's Grip case and
-- tests/table.spec.luau's row-drag cases already use — never by poking
-- `_pointerHandlers` directly, so a wiring mistake between the composite and
-- the renderer's ADR-0008 capture would show up here the same way it would
-- for a player.
--
-- TIME IS SCRIPTED (drag_velocity's own contract: "this module never reads
-- os.clock... a scripted clock replays a flick exactly"). `pointerWorld`
-- below builds the presenter with an explicit `now` option so `w.tick(dt)`
-- advances BOTH the presenter's motion clock (an explicit `dt`, same as
-- tests/row_actions.spec.luau's own `settle` helper) AND the same clock
-- `bindMotion`'s second argument hands this composite — the one legal time
-- source its `drag_velocity` tracker may read.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local row_actions = require("../src/controls/row_actions")
local fake_target = require("../tests/lib/fake_target")
local lt = require("./lib/large_text")
local text_metrics = require("../src/layout/text_metrics")
local themeSnapshot = require("../src/themes/snapshot")

local ROW = "/S/Row"
local HIT = ROW .. "/Content/Hit"
local TRAILING_TRAY = ROW .. "/TrayTrailingWhen/then/TrayTrailing"
local FRAME = 1 / 60

-- an explicit, realistic row width (a List/Table row is never as narrow as
-- its own text) — comfortably wider than the trailing tray, so the
-- open-at-half-tray and commit-at-60%-of-row thresholds land far apart
-- rather than crowding each other at the row's bare text-hug width.
local function content(id: string?)
	return LuauUI.UI.Text({
		id = id or "Body",
		text = "Row content",
		width = { type = "fixed", px = 400 },
		height = { type = "fixed", px = 48 },
	})
end

-- presenter harness with a SCRIPTED `now`: `w.tick(dt)` advances both the
-- presenter's own motion clock (explicit dt, deterministic regardless of
-- wall time — mirrors tests/row_actions.spec.luau's `settle`) and the value
-- `now()` returns, which `bindMotion`'s second argument threads into this
-- composite's own `drag_velocity` tracker (src/controls/row_actions.luau
-- `currentNow`).
local function pointerWorld(build: (core: any) -> any)
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
	local ra = build(core)
	local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } })
	local handle = pres.present(screen)
	pres.refresh()
	local w: any = { core = core, env = env, system = system, adapter = adapter, pres = pres, ra = ra, handle = handle }
	-- a "frame": advance the scripted clock, step the motion clock (explicit
	-- dt, deterministic), AND run the full sync pass — `pres.tick` alone only
	-- steps springs (presenter.luau `tickBody`: motionClock:step + pointer-
	-- dwell bookkeeping, nothing structural); `pres.refresh()` is the
	-- separate pass that runs `syncGeometry` (a live-found repro during this
	-- task: a drag that never paired tick with refresh left the just-
	-- revealed tray forever unmeasured, so `leadingWidth`/`trailingWidth`
	-- stayed frozen at 0 and every gesture settled closed no matter how far
	-- it dragged). A real host loop calls both every frame; so does this one.
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
	return w
end

-- a row with one trailing action ("delete"); `firedOpt` lets a caller
-- override fullSwipe per test (row-actions.md's per-edge form). `roleOpt`
-- (redteam item 4) lets a caller build the SAME shape with an explicit
-- `role` — nil (the default, used by every pre-existing caller) leaves the
-- action `normal`, unchanged.
local function trailingWorld(fullSwipeOpt: any?, roleOpt: ("normal" | "destructive")?)
	local fired: { string } = {}
	local w = pointerWorld(function(core)
		return row_actions.build(LuauUI, core, {
			id = "Row",
			content = content("Body"),
			trailing = {
				{
					id = "delete",
					label = "Delete",
					role = roleOpt,
					onAction = function()
						table.insert(fired, "delete")
					end,
				},
			},
			fullSwipe = fullSwipeOpt,
		})
	end)
	w.fired = fired
	return w
end

-- the settled trailing tray width, learned live (never hardcoded — the
-- house pattern tests/row_actions.spec.luau's own "5b. SPRING MOTION" test
-- uses) from a throwaway world built with the identical spec.
local function learnTrayWidth(): number
	local ref = trailingWorld()
	ref.ra._open("trailing")
	ref.settle()
	return -ref.ra.dump().offset
end

-- the row's own live solved width — the SAME `controller.rectOf` call
-- `currentRowWidth` (src/controls/row_actions.luau) makes internally, used
-- here only to construct a valid full-swipe-commit drag distance (>= 60% of
-- it) without guessing a pixel number that happens to work today.
local function rowWidthOf(w: any): number
	return w.handle.controller.rectOf(ROW).w
end

describe("RowActions pointer gesture (Task 5: axis lock, drag, flick, commit)", function()
	it("horizontal drag reveals; release past half-tray snaps open", function()
		local trayWidth = learnTrayWidth()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(85, 20) -- dx=-15: past the 8px axis lock, resolves horizontal
		w.tick(1.0) -- a long, calm gap: velocity's contribution to the release is negligible
		local releaseX = 100 - trayWidth * 0.75 -- well past half the tray
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		w.settle()
		expect(w.ra._isOpen()).toBe(true)
		expect(w.ra.dump().openEdge).toBe("trailing")
		expect(w.ra.dump().offset).toBeCloseTo(-trayWidth, 0.5)
		expect(#w.fired).toBe(0) -- a snap-open is not a commit
	end)

	it("release under half-tray snaps closed", function()
		local trayWidth = learnTrayWidth()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(85, 20)
		w.tick(1.0)
		local releaseX = 100 - trayWidth * 0.25 -- under half the tray
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		w.settle()
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().offset).toBe(0)
	end)

	it("vertical drag never moves the offset (axis lock)", function()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(102, 60) -- dx=2, dy=40: resolves vertical (ties go vertical too)
		expect(w.ra.dump().offset).toBe(0)
		w.tick(FRAME)
		w.adapter.pointerMove(140, 140) -- a LARGE further move; a declined gesture stays inert
		expect(w.ra.dump().offset).toBe(0)
		w.adapter.pointerUp(140, 140)
		expect(w.ra.dump().offset).toBe(0)
		expect(w.ra._isOpen()).toBe(false)
	end)

	it("a leftward flick (velocity) opens from a short drag", function()
		local trayWidth = learnTrayWidth()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(85, 20) -- dx=-15: past the lock, resolves horizontal
		w.tick(0.01)
		-- a SHORT total drag — well under the 50% distance-only open threshold —
		-- covered fast enough that the release-velocity projection crosses it
		-- anyway (row_actions_state.spec.luau's own worked example: "40px +
		-- (-600 px/s * 0.08s) = -88 -> open").
		local shortX = 100 - trayWidth * 0.3
		w.adapter.pointerMove(shortX, 20)
		w.adapter.pointerUp(shortX, 20)
		w.settle()
		expect(w.ra._isOpen()).toBe(true)
		expect(w.ra.dump().openEdge).toBe("trailing")
	end)

	-- REDTEAM ITEM 9 (MEDIUM): `currentDecision`'s "self-correcting within a
	-- frame or two" story (see its own header comment) assumes at least one
	-- `syncGeometry` (a `pres.refresh()`) lands somewhere between down and
	-- up — true of a real host frame loop, but NOT of a full gesture driven
	-- with ZERO ticks in between (down/move/up back-to-back, exactly as
	-- this test does): with `leadingWidth`/`trailingWidth` never measured
	-- (still exactly 0), a fresh row's first-ever flick used to settle
	-- CLOSED no matter how far it dragged, because `settle` saw `tray <= 0`
	-- on both edges. `w.tick` is never called here on purpose.
	it("down/move/up with ZERO ticks between (no syncGeometry ever ran): a real drag still opens", function()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "mouse")
		w.adapter.pointerMove(50, 20) -- dx = -50: past the lock, well past half the theme's buttonMinWidth (64)
		w.adapter.pointerUp(50, 20)
		w.settle() -- animation only, from here on — the decision is already made
		expect(w.ra._isOpen()).toBe(true)
		expect(w.ra.dump().openEdge).toBe("trailing")
	end)

	-- REDTEAM ITEM 4 (MAJOR — director ruling, SwiftUI behavior): the
	-- slide-off + height-collapse sequence is DESTRUCTIVE-only (see the
	-- "non-destructive" test below for the sibling behavior a `normal`-role
	-- first action gets instead). Explicit `role = "destructive"` here (it
	-- used to be implicit/unstated — the test's own name claimed "collapses"
	-- with nothing actually asserting a height change, which is exactly how
	-- the pre-fix code got away with collapsing EVERY role).
	it("full swipe commits (destructive): row slides off, collapses, onAction fires exactly once", function()
		local rowHeightBefore = 48 -- `content()`'s own fixed height (see the helper above)
		local w = trailingWorld(nil, "destructive")
		local rowWidth = rowWidthOf(w)
		w.adapter.pointerDown(HIT, 0, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(-15, 20) -- past the lock
		w.tick(1.0) -- negligible velocity: this commit is a DISTANCE commit
		local releaseX = -(rowWidth * 0.7) -- past the 60% full-swipe commit threshold
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		-- the collapse actually happened (not asserted before this fix wave —
		-- proves the destructive branch really took the slide+collapse path):
		-- step frame-by-frame and track the MINIMUM height reached along the
		-- way, since item 5 (below) makes the row recover its full height by
		-- the time the whole chain (through `close()`) finishes — the dip to
		-- ~0 is a real, if transient, part of the sequence.
		local minHeight = rowHeightBefore
		for _ = 1, 400 do
			w.tick(FRAME)
			local h = w.handle.controller.rectOf(ROW).h
			if h < minHeight then
				minHeight = h
			end
		end
		expect(#w.fired).toBe(1)
		expect(w.fired[1]).toBe("delete")
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().phase).toBe("closed")
		expect(minHeight).toBeCloseTo(0, 0.5)
	end)

	--[[ REVIEW FIX (hosted-mode round 2, D1) — THE STANDALONE MIRROR of the
		VirtualList case in tests/virtual_list_row_actions.spec.luau. The fix is
		in SHARED code (`commitLatched`, src/controls/row_actions.luau), so the
		hole was never hosted-only: a press landing while the row was parked a
		whole row width from home seeded `drag.startOffset` from the live `offset`,
		so a gesture that travelled 40px released with a magnitude past the 60%
		commit threshold — and deleted the row a second time.

		THE WINDOW MOVED, AND THE GUARANTEE DID NOT (device bug round 2026-08-12,
		finding C8a — see the header of tests/row_actions_motion.spec.luau). This
		case used to run to the FIRE and then assert `offset < -rowWidth/2`,
		"parked, mid-flight": the chain fired and only THEN put the row's paint
		back, springing it home from -400 over ~65 more frames with `committed`
		already cleared. That return flight is the second half of C8a — the row
		visibly reappearing before the owner's removal lands — and it is gone: the
		paint restore is deferred to the next `syncGeometry` and is a SNAP, so by
		the fire frame the row is already home.

		So the assertion is now made over the WHOLE trace rather than at one
		sampled frame — the row really did fly a whole width out and really was
		parked there while the commit played — and the re-swipe still lands
		immediately after the fire, which is still the moment `committed` clears.
		The guarantee this case exists for is untouched: exactly one fire. ]]
	it("a re-swipe the instant a commit clears cannot fire the action twice", function()
		local w = trailingWorld(nil, "destructive")
		local rowWidth = rowWidthOf(w)
		w.adapter.pointerDown(HIT, 0, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(-15, 20)
		w.tick(1.0)
		local releaseX = -(rowWidth * 0.7)
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		-- run the chain until the action has fired, watching how far out the row
		-- was actually carried on the way
		local firedAt = nil
		local deepest = 0
		for i = 1, 400 do
			w.tick(FRAME)
			deepest = math.min(deepest, w.ra.dump().offset)
			if firedAt == nil and #w.fired == 1 then
				firedAt = i
				break
			end
		end
		expect(firedAt).never().toBeNil()
		expect(deepest).toBeLessThan(-rowWidth * 0.5) -- it really was parked off-row
		-- ...and swipe again, right here — the frame `committed` cleared
		w.adapter.pointerDown(HIT, 0, 20, "mouse")
		w.tick(FRAME)
		w.adapter.pointerMove(-15, 20)
		w.tick(FRAME)
		w.adapter.pointerMove(-40, 20) -- a SHORT drag: nowhere near 60%
		w.tick(FRAME)
		w.adapter.pointerUp(-40, 20)
		w.settle(400)
		expect(#w.fired).toBe(1)
	end)

	-- the sibling half of the SwiftUI ruling: a NON-destructive first action
	-- fires immediately and the row springs back to CLOSED — never sliding
	-- off-screen, never collapsing height at all, exactly like tapping that
	-- same button directly in the revealed tray (row_actions.spec.luau's own
	-- "a successful (non-destructive) tray action..." case).
	it(
		"full swipe commits (non-destructive): fires once, springs back to CLOSED — no offscreen slide, no height change",
		function()
			local rowHeightBefore = 48
			local w = trailingWorld() -- default action carries no role (normal)
			local rowWidth = rowWidthOf(w)
			w.adapter.pointerDown(HIT, 0, 20, "mouse")
			w.tick(0.01)
			w.adapter.pointerMove(-15, 20)
			w.tick(1.0)
			local releaseX = -(rowWidth * 0.7) -- past the 60% full-swipe commit threshold
			w.adapter.pointerMove(releaseX, 20)
			w.tick(FRAME)
			w.adapter.pointerUp(releaseX, 20)
			-- the drag itself already left `offset` at `releaseX` the instant
			-- before any post-release animation runs — that is the baseline a
			-- correct non-destructive commit must never grow PAST (a destructive
			-- commit, by contrast, continues on toward -rowWidth from here).
			local baseline = -w.ra.dump().offset
			local peak = baseline
			for _ = 1, 400 do
				w.tick(FRAME)
				local off = -w.ra.dump().offset
				if off > peak then
					peak = off
				end
			end
			expect(#w.fired).toBe(1)
			expect(w.fired[1]).toBe("delete")
			expect(w.ra._isOpen()).toBe(false)
			expect(w.ra.dump().offset).toBe(0) -- sprung all the way back to CLOSED
			expect(peak).toBeLessThanOrEqual(baseline + 1) -- never continued toward the offscreen target
			expect(peak).toBeLessThan(rowWidth * 0.85) -- nowhere near a destructive commit's reach
			expect(w.handle.controller.rectOf(ROW).h).toBeCloseTo(rowHeightBefore, 0.5) -- NO collapse
		end
	)

	-- REDTEAM ITEM 1 (BLOCKER): `doCommitAction` sets `openEdge` to the
	-- committing edge BEFORE `retargetThen` aims the slide-off spring at the
	-- full row width — but `syncGeometry`'s own re-aim only ever gated on
	-- `drag == nil`, so with `openEdge` now naming an edge and no live drag,
	-- the VERY NEXT refresh re-aimed the SAME persistent spring back at
	-- `-trailingWidth` (the OPEN target), undoing the commit's own
	-- `retargetThen(offscreenTarget, ...)` before the spring ever got there.
	-- A full-swipe release therefore never actually reached `-rowWidth`: the
	-- row settled (and `onAction` fired) at `-trayWidth` instead — silently
	-- wrong even though `#fired == 1`/`_isOpen() == false` still held, which
	-- is why the existing "full swipe commits" test above never caught it.
	--
	-- Uses an EXPLICIT `role = "destructive"` action (item 4's later ruling,
	-- above): only a destructive commit still runs the offscreen slide-off +
	-- collapse chain this bug lives in — a non-destructive commit never
	-- retargets offscreen at all, so it cannot exercise this regression.
	it(
		"full-swipe commit (destructive) reaches the OFFSCREEN target, not just the tray width (regression: syncGeometry re-aim)",
		function()
			local trayWidth = learnTrayWidth()
			local w = trailingWorld(nil, "destructive")
			local rowWidth = rowWidthOf(w)
			w.adapter.pointerDown(HIT, 0, 20, "mouse")
			w.tick(0.01)
			w.adapter.pointerMove(-15, 20)
			w.tick(1.0)
			local releaseX = -(rowWidth * 0.7)
			w.adapter.pointerMove(releaseX, 20)
			w.tick(FRAME)
			w.adapter.pointerUp(releaseX, 20)
			local peak = 0
			for _ = 1, 400 do
				w.tick(FRAME)
				local off = -w.ra.dump().offset
				if off > peak then
					peak = off
				end
			end
			expect(peak).toBeGreaterThan(rowWidth * 0.95) -- reached the offscreen commit target...
			expect(peak).toBeGreaterThan(trayWidth + 1) -- ...not just the open tray width
			expect(#w.fired).toBe(1)
			expect(w.fired[1]).toBe("delete")
		end
	)

	-- REDTEAM ITEM 5 (MAJOR): `rowHeightOverride`/`committed` never reset
	-- after a destructive commit's own slide-off+collapse+close chain
	-- finished — a repro found the row permanently pinned at 0 height
	-- forever whenever the OWNER did not actually remove the row instance
	-- afterward (a throwing `onAction` that never mutated the data being the
	-- sharpest case, but ANY non-removing destructive action hit it): a
	-- "phantom row" — visually collapsed to nothing, its trays still fully
	-- mounted underneath, unable to ever open or commit again. Fixed by
	-- resetting both inside `close()` itself, the one seam every commit path
	-- already funnels through.
	local function fullSwipeCommit(w: any)
		local rowWidth = rowWidthOf(w)
		w.adapter.pointerDown(HIT, 0, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(-15, 20)
		w.tick(1.0)
		local releaseX = -(rowWidth * 0.7)
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		-- three chained springs (slide off, collapse, close's retarget-to-0)
		-- plus generous headroom for the fix's own post-close settle
		w.settle(600)
	end

	it(
		"a throwing destructive commit still returns the (un-removed) row to full height, closed, trays unmounted",
		function()
			local calls = 0
			local w = pointerWorld(function(core)
				return row_actions.build(LuauUI, core, {
					id = "Row",
					content = content("Body"),
					trailing = {
						{
							id = "boom",
							label = "Boom",
							role = "destructive",
							onAction = function()
								calls += 1
								error("kaboom")
							end,
						},
					},
				})
			end)
			fullSwipeCommit(w)
			expect(calls).toBe(1)
			expect(w.ra._isOpen()).toBe(false)
			expect(w.ra.dump().offset).toBe(0) -- not pinned at the offscreen commit target
			expect(w.handle.controller.rectOf(ROW).h).toBeCloseTo(48, 0.5) -- NOT stuck at 0
			expect(w.adapter.node(TRAILING_TRAY) == nil).toBe(true) -- trays unmounted (offset settled back to 0)
			-- further settling never refires the quarantined callback
			w.settle(120)
			expect(calls).toBe(1)
		end
	)

	it(
		"a successful destructive commit ALSO recovers when the owner keeps the row alive: offset 0, full height, and a later commit is reachable again",
		function()
			local rowHeightBefore = 48
			local w = trailingWorld(nil, "destructive")
			fullSwipeCommit(w)
			expect(#w.fired).toBe(1)
			expect(w.ra._isOpen()).toBe(false)
			expect(w.ra.dump().offset).toBe(0)
			expect(w.handle.controller.rectOf(ROW).h).toBeCloseTo(48, 0.5)
			expect(w.adapter.node(TRAILING_TRAY) == nil).toBe(true)
			-- `committed` reset to false: a SECOND full-swipe commit on this same
			-- still-alive row must be reachable, not permanently blocked.
			--
			-- REDTEAM FIX (item 4, MINOR; final-review-findings.md — "second
			-- commit on a recovered row never collapses"): the previous
			-- version of this test only ever counted fires — `ensureCollapse
			-- Spring`'s own early return (the REUSED, already-at-0 spring
			-- from the FIRST commit never got re-seeded to the row's current
			-- height) meant the second collapse's own target — 0 — was
			-- already where the spring sat, so it never actually MOVED: the
			-- row's painted height stayed at 48 the whole second commit,
			-- while `#fired` still silently reached 2. Tracked here the same
			-- way the very first "full swipe commits (destructive)" test
			-- above proves the FIRST collapse: step frame-by-frame and track
			-- the minimum height actually reached.
			local rowWidth = rowWidthOf(w)
			w.adapter.pointerDown(HIT, 0, 20, "mouse")
			w.tick(0.01)
			w.adapter.pointerMove(-15, 20)
			w.tick(1.0)
			local releaseX = -(rowWidth * 0.7)
			w.adapter.pointerMove(releaseX, 20)
			w.tick(FRAME)
			w.adapter.pointerUp(releaseX, 20)
			local minHeight = rowHeightBefore
			for _ = 1, 400 do
				w.tick(FRAME)
				local h = w.handle.controller.rectOf(ROW).h
				if h < minHeight then
					minHeight = h
				end
			end
			expect(#w.fired).toBe(2)
			expect(w.ra.dump().offset).toBe(0)
			expect(w.handle.controller.rectOf(ROW).h).toBeCloseTo(48, 0.5)
			expect(minHeight).toBeCloseTo(0, 0.5) -- the SECOND collapse actually moved, not stuck at 48
		end
	)

	it("commit with a throwing onAction still closes and does not refire", function()
		local calls = 0
		local w = pointerWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = content("Body"),
				trailing = {
					{
						id = "boom",
						label = "Boom",
						onAction = function()
							calls += 1
							error("kaboom")
						end,
					},
				},
			})
		end)
		local rowWidth = rowWidthOf(w)
		w.adapter.pointerDown(HIT, 0, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(-15, 20)
		w.tick(1.0)
		local releaseX = -(rowWidth * 0.7)
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		w.settle(400)
		expect(calls).toBe(1)
		expect(w.ra._isOpen()).toBe(false) -- the throw did not skip close() bookkeeping
		-- further settling never refires the quarantined callback
		w.settle(120)
		expect(calls).toBe(1)
	end)

	it("fullSwipe = { trailing = false } refuses to commit on trailing", function()
		local w = trailingWorld({ trailing = false })
		local rowWidth = rowWidthOf(w)
		w.adapter.pointerDown(HIT, 0, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(-15, 20)
		w.tick(1.0)
		-- a drag that WOULD have committed with fullSwipe on
		local releaseX = -(rowWidth * 0.9)
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		w.settle(120)
		expect(#w.fired).toBe(0)
		-- refused, not stranded: it still snaps open at the (rubber-banded) tray
		expect(w.ra._isOpen()).toBe(true)
		expect(w.ra.dump().openEdge).toBe("trailing")
	end)

	it("_commitFirst('trailing') fires the first trailing action once", function()
		local fired: { string } = {}
		local w = pointerWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = content("Body"),
				trailing = {
					{
						id = "delete",
						label = "Delete",
						onAction = function()
							table.insert(fired, "delete")
						end,
					},
					{
						id = "flag",
						label = "Flag",
						onAction = function()
							table.insert(fired, "flag")
						end,
					},
				},
			})
		end)
		-- no leading actions declared: false, never an error, never a stray fire
		expect(w.ra._commitFirst("leading")).toBe(false)
		expect(w.ra._commitFirst("trailing")).toBe(true)
		w.settle(400)
		expect(fired).toEqual({ "delete" }) -- the FIRST trailing action only, once
		expect(w.ra._isOpen()).toBe(false)
	end)

	--[[ THE REUSED SPRING (found by the hosted row-actions parity sweep, LuauUI
		row-actions perf mission Task 5; fixed in `onPointerUp`/`onPointerCancel`
		with `spring:snap(offset:get())`).

		A live drag stops the persistent reveal spring and drives `offset` DIRECTLY,
		and `ensureSpring` seeds a spring only when it CREATES one — so from the
		SECOND gesture on a row onward the spring stood wherever the last flight
		left it rather than where the finger is. A snap-back aims it at 0, which is
		exactly where a row that has already been closed once is parked: no steps,
		no writes, and the row stayed sitting at the drag's last offset with
		`_isOpen()` false and no tray to put it away. Measured before the fix, on
		this very shape: 0, then -20, then -40 — a row that ratchets further out of
		place with every short swipe a player makes.

		THE FIRST GESTURE WAS ALWAYS CORRECT, which is why the whole standalone
		corpus was green: every other case here swipes a fresh row exactly once.
		The three-swipe repetition IS the test. ]]
	it("a SECOND (and third) short swipe on the same row also snaps back to closed", function()
		local w = trailingWorld()
		for _ = 1, 3 do
			w.adapter.pointerDown(HIT, 100, 20, "mouse")
			w.tick(0.01)
			w.adapter.pointerMove(80, 20) -- dx = -20: past the lock, under half the tray
			w.tick(1.0) -- a long, calm gap: no flick in the release
			expect(w.ra.dump().offset).toBeCloseTo(-20, 0.001)
			w.adapter.pointerUp(80, 20)
			w.settle()
			expect(w.ra.dump().offset).toBe(0) -- home, EVERY time — never -20, -40, …
			expect(w.ra._isOpen()).toBe(false)
		end
		-- ...and the row still opens normally afterwards: the re-seed costs the
		-- spring its stale position, not its aim
		local trayWidth = learnTrayWidth()
		w.adapter.pointerDown(HIT, 100, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(85, 20)
		w.tick(1.0)
		local releaseX = 100 - trayWidth * 0.75
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		w.settle()
		expect(w.ra._isOpen()).toBe(true)
		expect(w.ra.dump().offset).toBeCloseTo(-trayWidth, 0.5)
		expect(#w.fired).toBe(0)
	end)

	it("a CANCELLED drag on a row that has already been opened once springs back too", function()
		-- the other end a manual drag can have (`onPointerCancel` -> `close()`),
		-- with the same stale-seed hole: proven on a row whose spring is already
		-- parked at 0 from a previous flight
		local w = trailingWorld()
		w.ra._open("trailing")
		w.settle()
		w.ra._close()
		w.settle()
		expect(w.ra.dump().offset).toBe(0)
		w.adapter.pointerDown(HIT, 100, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(80, 20)
		w.tick(1.0)
		expect(w.ra.dump().offset).toBeCloseTo(-20, 0.001)
		w.adapter.interruptCapture()
		w.settle()
		expect(w.ra.dump().offset).toBe(0)
		expect(w.ra._isOpen()).toBe(false)
	end)

	it("pointer cancel mid-drag springs back to closed", function()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(70, 20) -- past the lock, dragging open
		expect(w.ra.dump().offset < 0).toBe(true) -- live-tracking mid-drag
		w.adapter.interruptCapture() -- the adapter's own mid-gesture cancel (e.g. a modal stealing the drag)
		w.settle()
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().offset).toBe(0)
	end)

	-- Task 6 (artifacts/row-actions/touch-spike.md): mouse and touch are the
	-- ONLY two classes this gesture accepts now — a THIRD, exotic pointer
	-- type (pen/stylus) still declines outright, exactly the way touch used
	-- to under Task 5 (see the `RowActions touch gesture` describe block
	-- below for the touch-acceptance cases this test used to assert the
	-- opposite of). Proven through the REAL adapter capture, not just by code
	-- inspection.
	it("a pen press at the hit surface declines the capture (not mouse, not touch)", function()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "pen")
		w.adapter.pointerMove(20, 20) -- would fully open on mouse/touch; a declined capture ignores it
		w.adapter.pointerUp(20, 20)
		expect(w.ra.dump().offset).toBe(0)
		expect(w.ra._isOpen()).toBe(false)
	end)

	-- REVIEW FINDING 1 (MAJOR, device-video repro): syncGeometry used to
	-- re-aim the reveal spring toward `-trailingWidth` on EVERY sync whenever
	-- `openEdge` named an edge, with no awareness of a live drag — so a
	-- re-grab mid-snap-open-flight had its `spring:stop()` undone on the very
	-- next frame, and the row visibly drifted even while the player's finger
	-- held perfectly still (reviewer: "56.9px drift over 15 frames"). Drives
	-- the reviewer's EXACT scenario: open via gesture, release (spring
	-- flies), re-grab mid-flight, hold N frames, assert no drift; then keep
	-- dragging and assert it still tracks (the fix must not just freeze
	-- `offset` forever).
	it("re-grab mid snap-open flight: syncGeometry never fights a live drag (regression)", function()
		local trayWidth = learnTrayWidth()
		local w = trailingWorld()
		-- 1. gesture-open (NOT a commit): well past half the tray, well under
		-- the 60%-of-row commit floor; released calmly (negligible velocity)
		w.adapter.pointerDown(HIT, 100, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(0, 20) -- dx=-100
		w.tick(1.0)
		w.adapter.pointerUp(0, 20)
		expect(w.ra.dump().openEdge).toBe("trailing") -- settled to OPEN, not committed

		-- 2. let the snap-open spring fly a FEW frames — genuinely mid-flight
		-- (mirrors tests/row_actions.spec.luau's own "8 frames in: neither at
		-- rest nor fully revealed" idiom)
		for _ = 1, 8 do
			w.tick(FRAME)
		end
		local midFlight = w.ra.dump().offset
		-- confirmed mid-flight, not settled. The drag itself overdragged past
		-- the tray (fullSwipe's clampDrag never clamps against the tray at
		-- all, only the release VERDICT is bounded by rowWidth) to exactly
		-- -100, so this flight is built and seeded from THAT live value
		-- (`ensureSpring`'s first-ever build reads `offset:get()`) and
		-- animates UP toward `-trayWidth` (-83-ish) — i.e. `midFlight` sits
		-- BETWEEN -100 and -trayWidth here, not beyond it either way.
		expect(midFlight < 0).toBe(true)
		expect(math.abs(midFlight - -trayWidth)).toBeGreaterThan(1)

		-- 3. RE-GRAB right where the row visually is, and cross the axis lock
		local grabX = 500
		w.adapter.pointerDown(HIT, grabX, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(grabX - 15, 20) -- past the lock, resolves horizontal, spring:stop()
		local afterCross = w.ra.dump().offset
		expect(afterCross).toBeCloseTo(midFlight - 15, 0.01) -- clampDrag(startOffset+dx), unclamped

		-- 4. HOLD STILL: no further finger movement, but keep stepping paired
		-- tick+refresh frames — `syncGeometry` runs on every one. THE BUG: it
		-- used to re-aim the spring toward `-trailingWidth` every single time
		-- (since `openEdge` still names "trailing"), fighting the stop() from
		-- step 3 and dragging `offset` back toward the old target even though
		-- nothing touched the pointer.
		for _ = 1, 15 do
			w.tick(FRAME)
		end
		local afterHold = w.ra.dump().offset
		expect(afterHold).toBeCloseTo(afterCross, 0.5) -- NO drift while the finger held still

		-- 5. the drag still tracks afterward — the fix gates the RE-AIM, not
		-- the live drag path itself
		w.adapter.pointerMove(grabX - 60, 20)
		local tracked = w.ra.dump().offset
		expect(tracked).toBeCloseTo(midFlight - 60, 0.01)
		w.adapter.pointerUp(grabX - 60, 20)
	end)

	-- REVIEW FINDING 2 (IMPORTANT, director-visible fidelity gap): `settle`
	-- already used release velocity for the OPEN/CLOSE/COMMIT decision, but
	-- `_settleTo` never seeded the spring that actually ANIMATES it, so a
	-- fast flick and a slow calm release looked identical in motion. Two
	-- releases from the SAME live offset (so both resolve the identical
	-- verdict — open, not commit — isolating the ANIMATION speed from the
	-- DECISION), one calm (vx = 0 exactly, a long pause before release) and
	-- one a genuine flick (a fast final leg) — the flick must reach 90% of
	-- the open target in strictly fewer stepped frames.
	it("flick momentum reaches 90% of target in fewer stepped frames than a calm release", function()
		local trayWidth = learnTrayWidth()
		local targetX = 100 - trayWidth * 0.75 -- same final live offset for both releases

		-- CALM: long pause before release, samples collapse to the SAME point
		-- (the tracker's own window keeps at least two, both at `targetX`) ->
		-- velocity is exactly 0.
		local calm = trailingWorld()
		calm.adapter.pointerDown(HIT, 100, 20, "mouse")
		calm.tick(0.01)
		calm.adapter.pointerMove(85, 20) -- past the lock
		calm.tick(1.0)
		calm.adapter.pointerMove(targetX, 20)
		calm.tick(1.0) -- long calm pause before release
		calm.adapter.pointerUp(targetX, 20)

		-- FLICK: identical final live offset, but the LAST leg is covered
		-- fast (a real, large leftward velocity at release).
		local flick = trailingWorld()
		flick.adapter.pointerDown(HIT, 100, 20, "mouse")
		flick.tick(0.01)
		flick.adapter.pointerMove(85, 20)
		flick.tick(1.0)
		flick.adapter.pointerMove(targetX + trayWidth * 0.1, 20) -- short of the final point
		flick.tick(0.01) -- FAST final leg
		flick.adapter.pointerMove(targetX, 20)
		flick.adapter.pointerUp(targetX, 20)

		-- both resolved the SAME verdict (open, not commit) before comparing speed
		expect(calm.ra.dump().openEdge).toBe("trailing")
		expect(flick.ra.dump().openEdge).toBe("trailing")
		expect(calm.ra.dump().offset).toBeCloseTo(flick.ra.dump().offset, 0.01)

		local function framesTo90Percent(w: any): number
			local goal = trayWidth * 0.9
			for frame = 1, 200 do
				w.tick(FRAME)
				if math.abs(w.ra.dump().offset) >= goal then
					return frame
				end
			end
			return math.huge -- never reached: fails the comparison below honestly
		end
		local calmFrames = framesTo90Percent(calm)
		local flickFrames = framesTo90Percent(flick)
		expect(flickFrames < calmFrames).toBe(true)
	end)

	-- REVIEW FINDING 3 (IMPORTANT): the commit-vs-data-refresh dispose guard
	-- (doCommit's own comment: "never fire onAction for a row whose key no
	-- longer matches") worked when probed by hand but had no regression test
	-- pinning it. Also pins the converse (the guard must not over-block a
	-- commit that ISN'T raced).
	-- REDTEAM ITEM 4 note: both worlds below now build a DESTRUCTIVE action —
	-- after item 4's fix, only a destructive commit still has an async
	-- slide-off/collapse chain at all for a dispose to race mid-flight; a
	-- non-destructive commit fires and closes synchronously (see the
	-- "full swipe commits (non-destructive)" test above), so it can never
	-- reach the "mid-flight, nothing fired yet" window this test depends on.
	it("dispose mid-slide-off never fires onAction and never errors; a normal commit still fires once", function()
		-- a normal (unraced) commit still fires exactly once (the guard doesn't over-block)
		local normal = trailingWorld(nil, "destructive")
		local rowWidth = rowWidthOf(normal)
		normal.adapter.pointerDown(HIT, 0, 20, "mouse")
		normal.tick(0.01)
		normal.adapter.pointerMove(-15, 20)
		normal.tick(1.0)
		local releaseX = -(rowWidth * 0.7)
		normal.adapter.pointerMove(releaseX, 20)
		normal.tick(FRAME)
		normal.adapter.pointerUp(releaseX, 20)
		normal.settle(400)
		expect(#normal.fired).toBe(1)

		-- a commit raced by a data refresh (dispose mid-slide-off): never fires
		local raced = trailingWorld(nil, "destructive")
		local raced_rowWidth = rowWidthOf(raced)
		raced.adapter.pointerDown(HIT, 0, 20, "mouse")
		raced.tick(0.01)
		raced.adapter.pointerMove(-15, 20)
		raced.tick(1.0)
		local raced_releaseX = -(raced_rowWidth * 0.7)
		raced.adapter.pointerMove(raced_releaseX, 20)
		raced.tick(FRAME)
		raced.adapter.pointerUp(raced_releaseX, 20)
		-- a FEW frames into the slide-off: mid-flight, well before the
		-- collapse phase (let alone `onAction`) would ever start
		for _ = 1, 8 do
			raced.tick(FRAME)
		end
		expect(raced.ra.dump().offset).never().toBe(0) -- confirmed still mid-slide, not arrived
		expect(#raced.fired).toBe(0) -- nothing has fired yet either way

		-- the owner's "data refresh" — the keyed diff destroying this row
		-- instance (tests/row_actions.spec.luau's own "dispose mid-flight
		-- leaks nothing" pattern: dismiss the surface, then dispose the
		-- composite)
		local disposeOk = pcall(function()
			raced.pres.dismiss(raced.handle)
			raced.ra.dispose()
		end)
		expect(disposeOk).toBe(true) -- dispose itself must never error

		-- step WAY past where the slide-off, the collapse, AND onAction would
		-- all have completed if the guard didn't hold
		local stepOk = pcall(function()
			for _ = 1, 400 do
				raced.tick(FRAME)
			end
		end)
		expect(stepOk).toBe(true) -- stepping a disposed composite must never error
		expect(#raced.fired).toBe(0) -- onAction NEVER fired for the raced row
	end)
end)

-- Task 6 (artifacts/row-actions/touch-spike.md): touch is accepted through
-- the IDENTICAL tentative-accept + axis-lock-then-inert dance mouse already
-- uses (Task 5) — `onPointerDown` no longer declines `pointerType == "touch"`.
-- These duplicate a representative slice of Task 5's own mouse cases with
-- `pointerType = "touch"` at `pointerDown` (move/up inherit the class from
-- the adapter's own `pointerCapture.pointerType`, matching how a real capture
-- works), proving no branch anywhere in the gesture treats the two classes
-- differently past `onPointerDown`'s initial accept. The last three cases are
-- this row's real §C hot-switch citations (registry `RowActions.hotSwitch`,
-- see tests/conformance/controls_registry.luau) — now that touch is a second
-- live class that can genuinely touch `drag`-in-flight state, `hotSwitch =
-- false` would be dishonest; these are the real CARRY/CANCEL cases that make
-- it a real citation instead.
describe("RowActions touch gesture (Task 6: touch accepted, same axis-lock dance as mouse)", function()
	it("TOUCH: horizontal drag reveals; release past half-tray snaps open", function()
		local trayWidth = learnTrayWidth()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "touch")
		w.tick(0.01)
		w.adapter.pointerMove(85, 20) -- dx=-15: past the 8px axis lock, resolves horizontal
		w.tick(1.0)
		local releaseX = 100 - trayWidth * 0.75
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		w.settle()
		expect(w.ra._isOpen()).toBe(true)
		expect(w.ra.dump().openEdge).toBe("trailing")
		expect(w.ra.dump().offset).toBeCloseTo(-trayWidth, 0.5)
		expect(#w.fired).toBe(0)
	end)

	it("TOUCH: release under half-tray snaps closed", function()
		local trayWidth = learnTrayWidth()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "touch")
		w.tick(0.01)
		w.adapter.pointerMove(85, 20)
		w.tick(1.0)
		local releaseX = 100 - trayWidth * 0.25
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		w.settle()
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().offset).toBe(0)
	end)

	-- the platform-safety case the whole spike exists for: a vertical touch
	-- drag must go INERT (same as mouse), never move `offset` — so a real
	-- native Y-scroll `Body` around this row is free to own it (touch-spike.md
	-- finding: raw InputBegan/Changed/Ended are non-exclusive, non-gesture-
	-- recognized signals — accepting them is not, by the platform's own event
	-- model, a competing claim on the recognizer `ScrollingFrame` uses).
	it("TOUCH: vertical drag never moves the offset (axis lock, same inert dance as mouse)", function()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "touch")
		w.tick(0.01)
		w.adapter.pointerMove(102, 60) -- dx=2, dy=40: resolves vertical (ties go vertical too)
		expect(w.ra.dump().offset).toBe(0)
		w.tick(FRAME)
		w.adapter.pointerMove(140, 140) -- a LARGE further move; a declined-verdict gesture stays inert
		expect(w.ra.dump().offset).toBe(0)
		w.adapter.pointerUp(140, 140)
		expect(w.ra.dump().offset).toBe(0)
		expect(w.ra._isOpen()).toBe(false)
	end)

	it("TOUCH: a leftward flick (velocity) opens from a short drag", function()
		local trayWidth = learnTrayWidth()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "touch")
		w.tick(0.01)
		w.adapter.pointerMove(85, 20)
		w.tick(0.01)
		local shortX = 100 - trayWidth * 0.3
		w.adapter.pointerMove(shortX, 20)
		w.adapter.pointerUp(shortX, 20)
		w.settle()
		expect(w.ra._isOpen()).toBe(true)
		expect(w.ra.dump().openEdge).toBe("trailing")
	end)

	-- REDTEAM ITEM 4: explicit `role = "destructive"` — see the mouse-path
	-- sibling test's own comment above for why (only destructive commits
	-- still slide off and collapse).
	it("TOUCH: full swipe commits (destructive): row slides off, collapses, onAction fires exactly once", function()
		local w = trailingWorld(nil, "destructive")
		local rowWidth = rowWidthOf(w)
		w.adapter.pointerDown(HIT, 0, 20, "touch")
		w.tick(0.01)
		w.adapter.pointerMove(-15, 20)
		w.tick(1.0)
		local releaseX = -(rowWidth * 0.7)
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		w.settle(400)
		expect(#w.fired).toBe(1)
		expect(w.fired[1]).toBe("delete")
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().phase).toBe("closed")
	end)

	it("TOUCH: fullSwipe = { trailing = false } refuses to commit on trailing", function()
		local w = trailingWorld({ trailing = false })
		local rowWidth = rowWidthOf(w)
		w.adapter.pointerDown(HIT, 0, 20, "touch")
		w.tick(0.01)
		w.adapter.pointerMove(-15, 20)
		w.tick(1.0)
		local releaseX = -(rowWidth * 0.9)
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		w.settle(120)
		expect(#w.fired).toBe(0)
		expect(w.ra._isOpen()).toBe(true)
		expect(w.ra.dump().openEdge).toBe("trailing")
	end)

	it("hotSwitch: a touch press arriving mid-mouse-drag is declined; the mouse drag CARRIES uninterrupted", function()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(85, 20) -- resolves horizontal (mouse)
		local beforeAttempt = w.ra.dump().offset
		-- the adapter's own single-capture model ignores this outright
		-- (fake_target.luau pointerDown: "a live capture OWNS the pointer...
		-- ignored, never a steal") — never reaches this composite's own
		-- onPointerDown at all, exactly like a same-class second press would.
		w.adapter.pointerDown(HIT, 200, 20, "touch")
		expect(w.ra.dump().offset).toBe(beforeAttempt) -- the failed attempt touched nothing
		-- the mouse drag CARRIES: it keeps tracking afterward, unaffected —
		-- clampDrag(startOffset + dx), startOffset = 0 (a fresh row), dx = -40
		w.adapter.pointerMove(60, 20)
		expect(w.ra.dump().offset).toBeCloseTo(-40, 0.01)
		w.adapter.pointerUp(60, 20)
	end)

	it("hotSwitch: a mouse press arriving mid-touch-drag is declined; the touch drag CARRIES uninterrupted", function()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "touch")
		w.tick(0.01)
		w.adapter.pointerMove(85, 20) -- resolves horizontal (touch)
		local beforeAttempt = w.ra.dump().offset
		w.adapter.pointerDown(HIT, 200, 20, "mouse")
		expect(w.ra.dump().offset).toBe(beforeAttempt)
		w.adapter.pointerMove(60, 20)
		expect(w.ra.dump().offset).toBeCloseTo(60 - 100, 0.01)
		w.adapter.pointerUp(60, 20)
	end)

	-- same-class capability loss (the interpretation Table's own hotSwitch
	-- citations use for "pointer drag mid-flight + pointer capability lost")
	-- => CANCEL, mirroring the existing mouse case exactly.
	it("hotSwitch: touch pointer cancel mid-drag springs back to closed (capability lost => CANCEL)", function()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "touch")
		w.tick(0.01)
		w.adapter.pointerMove(70, 20) -- past the lock, dragging open
		expect(w.ra.dump().offset < 0).toBe(true)
		w.adapter.interruptCapture()
		w.settle()
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().offset).toBe(0)
	end)
end)

-- ===========================================================================
-- Task 7: the open-state coordinator + outside-tap/scroll dismissal
-- (docs/plans/row-actions-implementation.md Task 7; row_actions.newCoordinator,
-- public export `LuauUI.newRowActionsCoordinator`).
--
-- THE ROUND-7 LESSON (docs/plans/row-actions.md: "note the round-7 Zone-A
-- lesson: closing must not swallow unrelated clicks"). `outsideDismiss`
-- (src/input/contribution.luau) is the SAME seam PopupButton uses
-- (popup_button.luau:338-346), and the presenter's own onNodeTap dismiss path
-- (src/present/presenter.luau, "transient-popup outside-tap") SWALLOWS the tap
-- by default — `od.dismiss(); return` — which is exactly right for a modal-ish
-- popup (nothing else should have received that tap either) but exactly WRONG
-- for a row's tray, which sits inside a live list: closing row A on a tap that
-- actually landed on row B's own button must not eat that press. The fix
-- (this task) is `outsideDismiss.consume = false` on row_actions' own bundle
-- — a presenter-level opt-out, additive and off by default, so PopupButton's
-- existing swallow behavior is untouched. "does-not-swallow-unrelated-clicks"
-- below is the pin; it was run once against a deliberately reverted
-- `consume = true` and failed (firedB stayed empty) before this fix landed —
-- see the Task 7 report for the captured failure.
describe("RowActions Task 7: open-state coordinator + outside-tap/scroll dismissal", function()
	-- two rows sharing one coordinator, on a plain (non-scrolling) Screen —
	-- everything the coordinator itself needs, without a ScrollView's own
	-- machinery in the way. `content` is a real focusable Button (not the
	-- other describe blocks' bare Text) so "does the tap land on this row's
	-- OWN control" is provable, not just "did offset move".
	local function rowButtonContent(id: string, fired: { string })
		return LuauUI.UI.Button({
			id = id,
			label = "Row " .. id,
			width = { type = "fixed", px = 400 },
			height = { type = "fixed", px = 48 },
			onActivate = function()
				table.insert(fired, "tap")
			end,
		})
	end

	local function twoRowWorld()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local coordinator = row_actions.newCoordinator(core)
		local firedA: { string } = {}
		local firedB: { string } = {}
		local function trailingRow(rowId: string, fired: { string })
			return row_actions.build(LuauUI, core, {
				id = rowId,
				content = rowButtonContent("Body", fired),
				trailing = {
					{
						id = "delete",
						label = "Delete",
						onAction = function()
							table.insert(fired, "delete")
						end,
					},
				},
				coordinator = coordinator,
			})
		end
		local rowA = trailingRow("RowA", firedA)
		local rowB = trailingRow("RowB", firedB)
		local screen = LuauUI.UI.Screen({ id = "S", children = { rowA.blueprint, rowB.blueprint } })
		-- sinkNavigation: the same opt-in tests/paradigm_popup.spec.luau's own
		-- gamepad-Cancel world uses, so ButtonB reaches this screen's own
		-- contributions rather than leaking through as ordinary gameplay input.
		local handle = pres.present(screen, { sinkNavigation = true })
		pres.refresh()
		local w: any = {
			core = core,
			env = env,
			system = system,
			adapter = adapter,
			pres = pres,
			handle = handle,
			coordinator = coordinator,
			rowA = rowA,
			rowB = rowB,
			firedA = firedA,
			firedB = firedB,
		}
		function w.tick(dt: number)
			pres.tick(dt)
			pres.refresh()
		end
		function w.settle(frames: number?)
			for _ = 1, frames or 20 do
				w.tick(1 / 60)
			end
		end
		return w
	end

	it("opening row B closes row A (one-open policy)", function()
		local w = twoRowWorld()
		w.rowA._open("trailing")
		w.settle()
		expect(w.rowA._isOpen()).toBe(true)
		w.rowB._open("trailing")
		w.settle()
		expect(w.rowB._isOpen()).toBe(true)
		expect(w.rowA._isOpen()).toBe(false) -- claimed away, closed
	end)

	-- REDTEAM ITEM 7 (MAJOR, cross-row half): the coordinator's own `claim`
	-- used to close only the claimed-away row's TRAY (`_close`) — its MENU
	-- is independent state, so a row with BOTH its tray revealed (which is
	-- what actually claims the coordinator in the first place — opening
	-- the menu alone never does, see `open`'s own `coordinator.claim` vs.
	-- `openMenu`, which has none) AND its menu open on top of that used to
	-- have its menu — and its `transientScope` focus trap — stay armed
	-- while another row's gesture claimed the coordinator away from it.
	it("row B starting a horizontal gesture closes row A's OPEN MENU too, not just its tray", function()
		local w = twoRowWorld()
		w.rowA._open("trailing") -- claims the coordinator (this IS what `claimed` tracks)
		w.settle()
		expect(w.rowA._isOpen()).toBe(true)

		w.pres.focus.focusOn("/S/RowA/Content/Body")
		w.system.deviceKey("ButtonX", true)
		w.system.deviceKey("ButtonX", false)
		w.pres.refresh()
		expect(w.rowA.dump().menuOpen).toBe(true) -- BOTH tray and menu now open on row A

		-- crossing the axis lock alone claims the coordinator
		-- (`row_actions.build`'s own `onPointerMove`, Task 7's SECOND claim
		-- site) — well before any release/settle.
		w.adapter.pointerDown("/S/RowB/Content/Hit", 100, 20, "mouse")
		w.adapter.pointerMove(85, 20) -- dx = -15: past the 8px axis lock
		expect(w.rowA._isOpen()).toBe(false) -- tray closed (pre-existing behavior)
		expect(w.rowA.dump().menuOpen).toBe(false) -- menu ALSO closed, not stranded
		w.adapter.pointerUp(85, 20)
	end)

	it("scroll movement closes the open row (fire the observeScroll callback)", function()
		local w = twoRowWorld()
		w.rowA._open("trailing")
		w.settle()
		expect(w.rowA._isOpen()).toBe(true)

		-- a minimal stub controller — this proves `bindScroll` itself wires
		-- `controller.observeScroll` and reacts to ANY invocation (no
		-- distance/velocity threshold, matching iOS); ScrollView's own real
		-- delivery of `observeScroll` is native_scroll.spec.luau's proof, and
		-- the VStack world below drives it through a REAL ScrollView too.
		local observer: ((pos: { x: number, y: number }) -> ())? = nil
		local stubController = {
			observeScroll = function(_path: string, fn: (pos: { x: number, y: number }) -> ()): () -> ()
				observer = fn
				return function()
					observer = nil
				end
			end,
		}
		local unbind = w.coordinator.bindScroll(stubController, "/S/List")
		expect(observer ~= nil).toBe(true)
		local fireScroll = observer :: (pos: { x: number, y: number }) -> ()
		fireScroll({ x = 0, y = 5 })
		expect(w.rowA._isOpen()).toBe(false)
		unbind()
	end)

	it(
		"outside tap closes AND the tapped control still receives its press (does-not-swallow-unrelated-clicks)",
		function()
			local w = twoRowWorld()
			w.rowA._open("trailing")
			w.pres.refresh()
			expect(w.rowA._isOpen()).toBe(true)
			expect(#w.firedB).toBe(0)
			-- a tap on row B's OWN button: outside row A's subtree, so it closes
			-- A's tray, but it must still activate row B's button — the round-7
			-- Zone-A lesson this whole describe block exists to pin.
			w.adapter.tap("/S/RowB/Content/Body")
			w.pres.refresh()
			expect(w.rowA._isOpen()).toBe(false) -- A dismissed
			expect(w.firedB).toEqual({ "tap" }) -- B's press was NOT swallowed
		end
	)

	it("Cancel (handleCancel) closes an open row and reports handled", function()
		local w = twoRowWorld()
		w.rowA._open("trailing")
		w.pres.refresh()
		expect(w.rowA._isOpen()).toBe(true)
		-- Cancel is offered to the focused/longest-prefix contribution
		-- (presenter.luau's own ordering doc) — focus must sit inside row A's
		-- subtree for its handleCancel to be a candidate at all.
		w.pres.focus.focusOn("/S/RowA/Content/Body")
		w.system.deviceKey("ButtonB", true)
		w.system.deviceKey("ButtonB", false)
		w.pres.refresh()
		expect(w.rowA._isOpen()).toBe(false) -- handled: closed, not left open

		-- the converse (popup_button.luau's own proof shape): Cancel with
		-- nothing open does not falsely report handled — it falls through
		-- rather than swallowing the surface's own Cancel behavior.
		w.pres.focus.focusOn("/S/RowB/Content/Body")
		local cancelOk = pcall(function()
			w.system.deviceKey("ButtonB", true)
			w.system.deviceKey("ButtonB", false)
		end)
		expect(cancelOk).toBe(true)
		expect(w.rowB._isOpen()).toBe(false)
	end)

	it("a row unmounting while open clears its coordinator entry", function()
		local w = twoRowWorld()
		w.rowA._open("trailing")
		w.pres.refresh()
		expect(w.rowA._isOpen()).toBe(true)

		-- tear the whole presentation down first (the file's own "dispose
		-- mid-slide-off" idiom above), then dispose row A's own scope while
		-- it is still open. If the coordinator kept a stale reference to it,
		-- the NEXT claim would call `_close()` on a torn-down scope.
		local disposeOk = pcall(function()
			w.pres.dismiss(w.handle)
			w.rowA.dispose()
		end)
		expect(disposeOk).toBe(true)

		local claimOk = pcall(function()
			w.rowB._open("trailing")
		end)
		expect(claimOk).toBe(true) -- no stale `_close()` on the disposed row A
		expect(w.rowB._isOpen()).toBe(true)
	end)

	-- ======================================================================
	-- a REAL ScrollView > VStack of 3 wrapped rows sharing ONE coordinator —
	-- the actual consumer shape (docs/plans/row-actions.md: "a VStack/
	-- ScrollView list wraps rows itself and shares a public
	-- `newRowActionsCoordinator`"), driven end to end: one-open, scroll-close
	-- via the REAL `controller.observeScroll` (table.luau:2178's own idiom),
	-- and the no-swallow outside-tap, all through the real presenter+adapter.
	-- ======================================================================
	it(
		"a VStack of wrapped rows sharing newRowActionsCoordinator gets one-open + scroll-close + no-swallow behavior",
		function()
			local core = LuauUI.newCore()
			local env = LuauUI.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
			local system = LuauUI.newActionSystem(core)
			local adapter = fake_target.new()
			local pres = LuauUI.newPresenter(core, env, adapter, system)
			local coordinator = row_actions.newCoordinator(core)
			local fired: { [string]: { string } } = { RowA = {}, RowB = {}, RowC = {} }
			local function trailingRow(rowId: string)
				return row_actions.build(LuauUI, core, {
					id = rowId,
					content = rowButtonContent("Body", fired[rowId]),
					trailing = {
						{
							id = "delete",
							label = "Delete",
							onAction = function()
								table.insert(fired[rowId], "delete")
							end,
						},
					},
					coordinator = coordinator,
				})
			end
			local rowA, rowB, rowC = trailingRow("RowA"), trailingRow("RowB"), trailingRow("RowC")
			local screen = LuauUI.UI.Screen({
				id = "S",
				children = {
					LuauUI.UI.ScrollView({
						id = "List",
						height = { type = "fixed", px = 100 }, -- < 3 * 48px rows: genuinely overflows
						children = {
							LuauUI.UI.VStack({
								id = "Rows",
								children = { rowA.blueprint, rowB.blueprint, rowC.blueprint },
							}),
						},
					}),
				},
			})
			local handle = pres.present(screen)
			pres.refresh()
			local unbindScroll = coordinator.bindScroll(handle.controller, "/S/List")

			-- 1. ONE-OPEN: opening A, then B, closes A
			rowA._open("trailing")
			pres.refresh()
			expect(rowA._isOpen()).toBe(true)
			rowB._open("trailing")
			pres.refresh()
			expect(rowB._isOpen()).toBe(true)
			expect(rowA._isOpen()).toBe(false)

			-- 2. SCROLL CLOSES: any movement on the real ScrollView host, via the
			-- real `controller.observeScroll` mirror (native_scroll.spec.luau's
			-- own `driveScroll` idiom simulates the engine side)
			adapter.driveScroll("/S/List", { x = 0, y = 20 })
			expect(rowB._isOpen()).toBe(false)

			-- 3. OUTSIDE TAP DOES NOT SWALLOW: open C, tap A's own button —
			-- C closes, A's press still fires
			rowC._open("trailing")
			pres.refresh()
			expect(rowC._isOpen()).toBe(true)
			expect(#fired.RowA).toBe(0)
			adapter.tap("/S/List/Rows/RowA/Content/Body")
			pres.refresh()
			expect(rowC._isOpen()).toBe(false) -- C dismissed
			expect(fired.RowA).toEqual({ "tap" }) -- A's own press was NOT swallowed

			unbindScroll()
		end
	)
end)

-- ===========================================================================
-- Task 8: keyboard Delete + the Shift+Return/ButtonX action menu
-- (docs/plans/row-actions-implementation.md Task 8, task-8-brief.md).
--
-- SHIFT+RETURN SHIPPED IN TASK 8B (this describe block covers the gamepad
-- ButtonX half and keyboard Delete/Backspace, which never collided with
-- anything — `Delete`/`Backspace` are unclaimed elsewhere in the shipped
-- system). Task 8 itself left Shift+Return unbound — NEEDS_CONTEXT — because
-- `Return` was already the base screen's own Activate key
-- (presenter.luau:2528: `activate.bind({ keyCode = "Return" })`), IAS
-- bindings carried no modifier slot at all, and a focused leaf's own
-- `onActivate` fires UNCONDITIONALLY before any contribution or modifier
-- state is consulted (presenter.luau `dispatchActivate` step 1) — so a
-- second context bound to bare `Return` would either double-fire alongside
-- Activate on every SHIFTED press whenever the focused content is itself
-- activatable (exactly `focusableBody` below), or silently eat PLAIN Return
-- for the whole row if it sank to avoid that. Task 8b's fix is an additive
-- `modifiers` slot on `action.bind` (src/input/actions.luau +
-- src/client/roblox_input.luau): see "RowActions Task 8b: the action menu
-- (Shift+Return)" below for the shipped tests, including the double-fire
-- regression test this whole follow-up task exists to prevent.
local ROW_ACTIONS_KEY_FRAME = 1 / 60

-- a focusable content Button — deliberately, not the bare `content()` Text
-- helper above (which cannot hold focus at all): "the wrapper's content
-- subtree holding focus" (brief) needs something IN content that actually
-- can. Carries its OWN `onActivate` on request, so a scoped binding that DID
-- collide with Activate would show up in a test using it.
local function focusableBody(id: string, fired: { string }?): any
	return LuauUI.UI.Button({
		id = id,
		label = "Row",
		width = { type = "fixed", px = 400 },
		height = { type = "fixed", px = 48 },
		onActivate = if fired ~= nil
			then function()
				table.insert(fired :: { string }, "activate")
			end
			else nil,
	})
end

-- presenter harness mirroring `pointerWorld` above (a scripted clock via
-- `bindMotion`'s `now`, needed for the commit path's springs), plus the
-- keyboard focus/press helpers Task 8's tests need that the pointer/touch
-- describe blocks above did not.
local function keyboardWorld(build: (core: any) -> any): any
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
	local ra = build(core)
	local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } })
	local handle = pres.present(screen, { sinkNavigation = true })
	pres.refresh()
	local w: any = { core = core, env = env, system = system, adapter = adapter, pres = pres, ra = ra, handle = handle }
	function w.tick(dt: number)
		clockTime += dt
		pres.tick(dt)
		pres.refresh()
	end
	function w.settle(frames: number?)
		for _ = 1, frames or 90 do
			w.tick(ROW_ACTIONS_KEY_FRAME)
		end
	end
	function w.press(key: string)
		system.deviceKey(key, true)
		system.deviceKey(key, false)
	end
	-- Task 8b: a full Shift+Return chord — shift down (a real key event,
	-- not a bare field write, same idiom `keyboard_navigation.spec.luau` and
	-- `table.spec.luau`'s own shift-Traverse/reorder tests already use),
	-- then Return down+up, then shift up. Physical ordering (shift always
	-- precedes the main key in a real chord), not an artificial invariant.
	function w.pressShiftReturn()
		system.deviceKey("LeftShift", true)
		system.deviceKey("Return", true)
		system.deviceKey("Return", false)
		system.deviceKey("LeftShift", false)
	end
	return w
end

describe("RowActions Task 8: keyboard Delete", function()
	it("Delete on a focused row fires the first destructive action", function()
		local fired: { string } = {}
		local w = keyboardWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = focusableBody("Body"),
				trailing = {
					{
						id = "delete",
						role = "destructive",
						label = "Delete",
						onAction = function()
							table.insert(fired, "delete")
						end,
					},
				},
			})
		end)
		w.pres.focus.focusOn("/S/Row/Content/Body")
		w.press("Delete")
		w.settle(400)
		expect(fired).toEqual({ "delete" })
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().phase).toBe("closed")
	end)

	it("Backspace does the same as Delete", function()
		local fired: { string } = {}
		local w = keyboardWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = focusableBody("Body"),
				trailing = {
					{
						id = "delete",
						role = "destructive",
						label = "Delete",
						onAction = function()
							table.insert(fired, "delete")
						end,
					},
				},
			})
		end)
		w.pres.focus.focusOn("/S/Row/Content/Body")
		w.press("Backspace")
		w.settle(400)
		expect(fired).toEqual({ "delete" })
	end)

	it(
		"Delete searches trailing before leading, and finds the destructive action even when it is not first in its edge's list",
		function()
			local fired: { string } = {}
			local w = keyboardWorld(function(core)
				return row_actions.build(LuauUI, core, {
					id = "Row",
					content = focusableBody("Body"),
					leading = {
						{
							id = "flag-lead",
							role = "normal",
							label = "Flag",
							onAction = function()
								table.insert(fired, "flag-lead")
							end,
						},
						{
							id = "delete-lead",
							role = "destructive",
							label = "Delete (leading)",
							onAction = function()
								table.insert(fired, "delete-lead")
							end,
						},
					},
					trailing = {
						{
							id = "flag-trail",
							role = "normal",
							label = "Flag",
							onAction = function()
								table.insert(fired, "flag-trail")
							end,
						},
						{
							id = "delete-trail",
							role = "destructive",
							label = "Delete (trailing)",
							onAction = function()
								table.insert(fired, "delete-trail")
							end,
						},
					},
				})
			end)
			w.pres.focus.focusOn("/S/Row/Content/Body")
			w.press("Delete")
			-- checked BEFORE settling (a full settle already runs `close()`,
			-- which resets `openEdge` to nil): the commit targets "trailing"
			-- immediately, which is the proof that the SEARCH ORDER (trailing
			-- first) and the ROLE lookup (not "the edge's first action" —
			-- `_commitFirst`'s own assumption, which would have targeted
			-- "flag-trail" instead) both hold.
			expect(w.ra.dump().openEdge).toBe("trailing")
			w.settle(400)
			expect(fired).toEqual({ "delete-trail" })
			expect(w.ra.dump().phase).toBe("closed")
		end
	)

	it(
		"Delete does nothing when no destructive action exists anywhere — and never registers a binding (the key reaches a sibling consumer untouched)",
		function()
			local core = LuauUI.newCore()
			local env = LuauUI.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
			local system = LuauUI.newActionSystem(core)
			local adapter = fake_target.new()
			local pres = LuauUI.newPresenter(core, env, adapter, system)
			local fired: { string } = {}
			local ra = row_actions.build(LuauUI, core, {
				id = "Row",
				content = focusableBody("Body"),
				trailing = {
					{
						id = "flag",
						role = "normal",
						label = "Flag",
						onAction = function()
							table.insert(fired, "flag")
						end,
					},
				},
			})
			local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } })
			pres.present(screen, { sinkNavigation = true })
			pres.refresh()
			-- a SIBLING consumer bound directly, bypassing row_actions entirely:
			-- row_actions creates its OWN keys context with `sink = true`
			-- (brief: own the key while scoped-active) — if it registered a
			-- Delete binding at all, even one that never fires anything, a
			-- sinking, higher-priority context would still consume the key
			-- before this lower-priority one ever saw it. Firing here proves
			-- no such context was ever created.
			local sibling = system.createContext({ name = "Sibling", priority = 1 })
			local siblingDelete = sibling.createAction("SiblingDelete", "Bool")
			siblingDelete.bind({ keyCode = "Delete" })
			local siblingFired = 0
			siblingDelete.onPressed(function()
				siblingFired += 1
			end)
			pres.focus.focusOn("/S/Row/Content/Body")
			local ok = pcall(function()
				system.deviceKey("Delete", true)
				system.deviceKey("Delete", false)
			end)
			pres.refresh()
			expect(ok).toBe(true) -- no error either
			expect(#fired).toBe(0)
			expect(ra._isOpen()).toBe(false)
			expect(siblingFired).toBe(1) -- the key reached the sibling: nothing shadowed it
		end
	)

	it("Delete does nothing while focus is outside this row (scoped to the content subtree)", function()
		local fired: { string } = {}
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
		local ra = row_actions.build(LuauUI, core, {
			id = "Row",
			content = focusableBody("Body"),
			trailing = {
				{
					id = "delete",
					role = "destructive",
					label = "Delete",
					onAction = function()
						table.insert(fired, "delete")
					end,
				},
			},
		})
		local other = LuauUI.UI.Button({
			id = "Other",
			label = "Other",
			width = { type = "fixed", px = 200 },
			height = { type = "fixed", px = 48 },
		})
		local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint, other } })
		pres.present(screen, { sinkNavigation = true })
		pres.refresh()
		pres.focus.focusOn("/S/Other")
		system.deviceKey("Delete", true)
		system.deviceKey("Delete", false)
		pres.refresh()
		expect(#fired).toBe(0)
		expect(ra._isOpen()).toBe(false)
	end)
end)

describe("RowActions Task 8: the action menu — WHERE it lands", function()
	--[[ LIVE DEFECT, found 2026-08-13 by a placement-prop audit and fixed with the
		Group C flight round (same file, same trap one container over).

		`anchor`/`offsetX`/`offsetY` are read by a node's PARENT, and only by an
		`anchor`-kind one. The menu's `Menu` node IS a `UI.Anchor`, but it declared
		those three props on ITSELF, where its parent is the `UI.Screen` the menu is
		presented as — a VSTACK, which reads none of them. So the menu was placed at
		the ORIGIN of its surface instead of at its trigger. Measured before the fix:
		trigger row at (20, 148, 760x48), `menuOx/menuOy` correctly computed as
		(20, 196), menu solved at x = 0, y = 0 — silently, with
		`controller.diagnostics()` empty.

		WHY NO EXISTING CASE SAW IT: every other menu test uses `keyboardWorld`,
		whose screen has no padding and whose row sits at the top, so the trigger's
		own coordinates ARE (0, 0) and the wrong answer and the right one are the
		same number. This world deliberately pushes the row away from the origin on
		BOTH axes, which is the whole instrument. ]]
	local function offsetMenuWorld(): any
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local ra = row_actions.build(LuauUI, core, {
			id = "Row",
			content = focusableBody("Body"),
			trailing = {
				{ id = "delete", role = "destructive", label = "Delete", onAction = function() end },
				{ id = "flag", role = "normal", label = "Flag", onAction = function() end },
			},
		})
		-- padding on the screen and a tall spacer above the row: the trigger's own
		-- screen coordinates are now (20, 148), which no origin can be mistaken for
		local screen = LuauUI.UI.Screen({
			id = "S",
			padding = 20,
			children = {
				LuauUI.UI.VStack({
					id = "Cage",
					gap = 8,
					width = { type = "fill", weight = 1 },
					children = {
						LuauUI.UI.Box({ id = "Spacer", height = { type = "fixed", px = 120 }, surface = "base" }),
						ra.blueprint,
					},
				}),
			},
		})
		local handle = pres.present(screen, { sinkNavigation = true })
		pres.refresh()
		return { core = core, adapter = adapter, pres = pres, ra = ra, handle = handle, system = system }
	end

	--[[ RULING 4 (director, 2026-08-13): "flip the menu above the trigger when it
		would overflow" — standard platform behaviour, over clamping to the edge,
		because a clamp lets the menu cover its own trigger.

		THE MEASUREMENT THAT MADE IT A RULING: a trigger at y=508 on a 600px viewport
		put the menu at y=556..629 — 29px past the bottom. An `anchor` parent emits no
		overflow diagnostic for a child it places, so nothing in the suite or the
		sweeps could see it; only arithmetic on the solved rect can.

		The fixture is `offsetMenuWorld` with a taller spacer and an `env` (the flip
		needs the viewport height, and both shipped hosts pass one). 20 padding + 480
		spacer + 8 gap = a trigger at exactly y=508, which is the reported case. ]]
	local function bottomMenuWorld(spacerPx: number, withEnv: boolean?, viewportH: number?): any
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = viewportH or 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local ra = row_actions.build(LuauUI, core, {
			id = "Row",
			content = focusableBody("Body"),
			env = if withEnv == false then nil else env,
			trailing = {
				{ id = "delete", role = "destructive", label = "Delete", onAction = function() end },
				{ id = "flag", role = "normal", label = "Flag", onAction = function() end },
			},
		})
		local screen = LuauUI.UI.Screen({
			id = "S",
			padding = 20,
			children = {
				LuauUI.UI.VStack({
					id = "Cage",
					gap = 8,
					width = { type = "fill", weight = 1 },
					children = {
						LuauUI.UI.Box({
							id = "Spacer",
							height = { type = "fixed", px = spacerPx },
							surface = "base",
						}),
						ra.blueprint,
					},
				}),
			},
		})
		local handle = pres.present(screen, { sinkNavigation = true })
		pres.refresh()
		local w: any =
			{ core = core, adapter = adapter, pres = pres, ra = ra, handle = handle, system = system, env = env }
		function w.openMenu()
			w.pres.focus.focusOn("/S/Cage/Row/Content/Body")
			w.system.deviceKey("ButtonX", true)
			w.system.deviceKey("ButtonX", false)
			w.pres.refresh()
			expect(w.ra.dump().menuOpen).toBe(true)
		end
		function w.menuRect(): any
			local node = w.adapter.node("/RowActionsMenu-Row/Menu/MenuRows")
			expect(node).never().toBeNil()
			return node.rect
		end
		function w.triggerRect(): any
			return w.handle.controller.screenRectOf("/S/Cage/Row")
		end
		return w
	end

	it("THE CASE: a trigger near the bottom would put the menu PAST the viewport", function()
		-- the control that makes the flip mean something — without it, "the menu is
		-- above the trigger" is equally explained by "it was always above"
		local w = bottomMenuWorld(480)
		local trigger = w.triggerRect()
		expect(trigger.y).toBe(508) -- the reported number, reproduced
		w.openMenu()
		local menu = w.menuRect()
		expect(`below-placement would overflow: {trigger.y + trigger.h + menu.h > 600}`).toBe(
			"below-placement would overflow: true"
		)
	end)

	it("...so it FLIPS above the trigger, wholly inside the viewport", function()
		local w = bottomMenuWorld(480)
		local trigger = w.triggerRect()
		w.openMenu()
		local menu = w.menuRect()
		-- ABOVE: its bottom edge sits exactly on the trigger's top
		expect(menu.y + menu.h).toBe(trigger.y)
		-- ...and every row travelled with it, rather than one node moving
		local first = w.adapter.node("/RowActionsMenu-Row/Menu/MenuRows/Action:delete")
		expect(first.rect.y).toBe(menu.y)
		-- WHOLLY ON SCREEN, both edges — the actual requirement
		expect(`top inside: {menu.y >= 0}`).toBe("top inside: true")
		expect(`bottom inside: {menu.y + menu.h <= 600}`).toBe("bottom inside: true")
		-- and it never covers its own trigger, which is what a clamp would have done
		expect(`clear of the trigger: {menu.y + menu.h <= trigger.y}`).toBe("clear of the trigger: true")
		expect(menu.x).toBe(trigger.x) -- the horizontal placement is untouched
		expect(#w.handle.controller.diagnostics()).toBe(0)
	end)

	it("a trigger with room BELOW still opens below it — the flip is conditional", function()
		local w = bottomMenuWorld(120)
		local trigger = w.triggerRect()
		w.openMenu()
		local menu = w.menuRect()
		expect(menu.y).toBe(trigger.y + trigger.h)
		expect(`fits below: {menu.y + menu.h <= 600}`).toBe("fits below: true")
	end)

	it("the predicted height the flip DECIDES on is the height the solver PAINTS", function()
		--[[ The flip has to know the menu's height before the menu exists, so it
			computes `n * controlSizes.compact.height + (n - 1) * strokes.hairline`
			from the same live theme snapshot the solver resolves those names against.
			That is exact rather than approximate ONLY while `MenuRows` stays a
			padding-free VStack of fixed-height rows — so this pins the arithmetic
			against the solved rect. Add padding or a surface inset to the menu and
			this case reddens instead of the flip silently mis-deciding. ]]
		local w = bottomMenuWorld(480)
		w.openMenu()
		-- THE NUMBER THIS FILE ACTUALLY DECIDES ON (`dump().menuHeightPx`), not a
		-- second copy of the arithmetic written here: comparing the test's own sum
		-- against the solver would pass just as happily while `computeMenuAnchor`
		-- flipped on a different, wrong height.
		expect(w.ra.dump().menuHeightPx).toBe(w.menuRect().h)
		-- ...and it is the shape it claims to be, so the pin above is not circular
		local raw = w.env:get("themeMetrics"):get()
		local metrics = if type(raw) == "table" and type(raw.controls) == "table" then raw else themeSnapshot.neutral()
		local rowH = themeSnapshot.resolveNumber(metrics, "controlSizes.compact.height") or 0
		local gap = themeSnapshot.resolveNumber(metrics, "strokes.hairline") or 0
		expect(w.menuRect().h).toBe(2 * rowH + gap) -- two actions in this fixture
	end)

	it("NEGATIVE CONTROL: with no room ABOVE either, it stays BELOW rather than flipping", function()
		--[[ The flip is two conditions, not one, and this is the second. A menu too
			tall for the space above must NOT flip: partly clipped at the bottom is
			one problem, and partly clipped at the TOP while also upside down from its
			trigger is two. Without this case a gate that dropped the room-above test
			passes everything else here (measured — mutation M10).

			A 140px-tall window: the trigger lands at y=40 (20 padding + 12 spacer + 8
			gap), so the below-placement overflows AND the menu is taller than the 40px
			above it. ]]
		local w = bottomMenuWorld(12, true, 140)
		local trigger = w.triggerRect()
		w.openMenu()
		local menu = w.menuRect()
		expect(`overflows below: {trigger.y + trigger.h + menu.h > 140}`).toBe("overflows below: true")
		expect(`no room above: {trigger.y - menu.h < 0}`).toBe("no room above: true")
		expect(menu.y).toBe(trigger.y + trigger.h) -- still below, unflipped
	end)

	--[[ WITHOUT AN `env` THERE IS NO VIEWPORT TO STAY INSIDE, and the menu keeps its
		pre-ruling placement. Both shipped hosts (`table.luau`, `virtual_list.luau`)
		thread `spec.env` through, so this is the bare-standalone degrade, stated
		rather than discovered. ]]
	it("a standalone row with no `env` cannot flip, and says so by not flipping", function()
		local w = bottomMenuWorld(480, false)
		local trigger = w.triggerRect()
		w.openMenu()
		expect(w.menuRect().y).toBe(trigger.y + trigger.h)
	end)

	it("the menu is placed at its TRIGGER, not at the origin of its own surface", function()
		local w = offsetMenuWorld()
		local trigger = w.handle.controller.screenRectOf("/S/Cage/Row")
		expect(trigger).never().toBeNil()
		expect(trigger.x > 0).toBe(true) -- the fixture's whole point
		expect(trigger.y > 0).toBe(true)
		w.pres.focus.focusOn("/S/Cage/Row/Content/Body")
		w.system.deviceKey("ButtonX", true)
		w.system.deviceKey("ButtonX", false)
		w.pres.refresh()
		expect(w.ra.dump().menuOpen).toBe(true)
		-- the menu is its OWN presented surface, so its rects live on the adapter,
		-- not on the row screen's controller
		local rows = w.adapter.node("/RowActionsMenu-Row/Menu/MenuRows")
		expect(rows).never().toBeNil()
		expect(rows.rect.x).toBe(trigger.x)
		expect(rows.rect.y).toBe(trigger.y + trigger.h) -- just below the row, popup_button's rule
		-- ...and every row of it travels with the menu, rather than one node moving
		local first = w.adapter.node("/RowActionsMenu-Row/Menu/MenuRows/Action:delete")
		expect(first).never().toBeNil()
		expect(first.rect.x).toBe(trigger.x)
		expect(first.rect.y).toBe(trigger.y + trigger.h)
		--[[ ...and the ANCHOR'S OWN BOX CONTAINS WHAT IT PLACES. An `anchor` node
			left content-sized measures the union of its children WITHOUT their
			offsets, so it would report a 91x73 box at (0, 0) while painting its menu
			at (20, 556) — a container whose rect does not contain its own child, the
			"painted at a size nobody measured" family
			(docs/lessons/measure-the-requirement-not-the-render.md). Filling the
			edge-to-edge surface makes the box honest AND makes the anchor's inner
			origin the window origin, which is the space `computeMenuAnchor` measures
			the trigger in. ]]
		local anchorBox = w.adapter.node("/RowActionsMenu-Row/Menu")
		expect(anchorBox).never().toBeNil()
		expect(anchorBox.rect.x <= rows.rect.x).toBe(true)
		expect(anchorBox.rect.y <= rows.rect.y).toBe(true)
		expect(anchorBox.rect.x + anchorBox.rect.w >= rows.rect.x + rows.rect.w).toBe(true)
		expect(anchorBox.rect.y + anchorBox.rect.h >= rows.rect.y + rows.rect.h).toBe(true)
		expect(#w.handle.controller.diagnostics()).toBe(0)
	end)
end)

describe("RowActions Task 8: the action menu (ButtonX)", function()
	it(
		"ButtonX opens the menu, entering focus on its first row; Activate on a non-destructive item runs it exactly once and closes",
		function()
			local fired: { string } = {}
			local w = keyboardWorld(function(core)
				return row_actions.build(LuauUI, core, {
					id = "Row",
					content = focusableBody("Body"),
					trailing = {
						{
							id = "flag",
							role = "normal",
							label = "Flag",
							onAction = function()
								table.insert(fired, "flag")
							end,
						},
					},
				})
			end)
			w.pres.focus.focusOn("/S/Row/Content/Body")
			w.press("ButtonX")
			w.pres.refresh()
			expect(w.ra.dump().menuOpen).toBe(true)
			expect(w.pres.focus.focused:get()).toBe("/RowActionsMenu-Row/Menu/MenuRows/Action:flag")
			w.press("Return") -- Activate the focused (only) menu row
			w.pres.refresh()
			expect(fired).toEqual({ "flag" })
			expect(w.ra.dump().menuOpen).toBe(false)
			expect(w.adapter.node("/RowActionsMenu-Row/Menu/MenuRows")).toBe(nil) -- rows really unmounted
			expect(w.pres.focus.focused:get()).toBe("/S/Row/Content/Body") -- restored
		end
	)

	it("lists every action, leading then trailing, in document order", function()
		local w = keyboardWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = focusableBody("Body"),
				leading = {
					{ id = "archive", role = "normal", label = "Archive", onAction = function() end },
				},
				trailing = {
					{ id = "flag", role = "normal", label = "Flag", onAction = function() end },
					{ id = "delete", role = "destructive", label = "Delete", onAction = function() end },
				},
			})
		end)
		w.pres.focus.focusOn("/S/Row/Content/Body")
		w.press("ButtonX")
		w.pres.refresh()
		-- leading first (its only entry), then trailing in its own declared
		-- order — proven by walking Navigate one step at a time rather than
		-- reading internal state, so this is the same order a keyboard/
		-- gamepad player actually experiences.
		expect(w.pres.focus.focused:get()).toBe("/RowActionsMenu-Row/Menu/MenuRows/Action:archive")
		w.press("Down")
		expect(w.pres.focus.focused:get()).toBe("/RowActionsMenu-Row/Menu/MenuRows/Action:flag")
		w.press("Down")
		expect(w.pres.focus.focused:get()).toBe("/RowActionsMenu-Row/Menu/MenuRows/Action:delete")
	end)

	it(
		"a destructive action from the menu runs the full commit sequence (slide-off + collapse), not a bare callback",
		function()
			local fired: { string } = {}
			local w = keyboardWorld(function(core)
				return row_actions.build(LuauUI, core, {
					id = "Row",
					content = focusableBody("Body"),
					trailing = {
						{
							id = "delete",
							role = "destructive",
							label = "Delete",
							onAction = function()
								table.insert(fired, "delete")
							end,
						},
					},
				})
			end)
			w.pres.focus.focusOn("/S/Row/Content/Body")
			w.press("ButtonX") -- open the menu
			w.pres.refresh()
			w.press("Return") -- Activate the focused (only, destructive) menu row
			w.pres.refresh()
			-- NOT a bare callback: it has not fired yet — it fires only after
			-- the slide-off + collapse sequence settles (`doCommitAction`'s own
			-- guarantee, shared with the gesture and keyboard-Delete paths).
			expect(#fired).toBe(0)
			expect(w.ra.dump().menuOpen).toBe(false) -- the menu itself closed immediately
			expect(w.ra.dump().openEdge).toBe("trailing") -- the row is visibly committing
			w.settle(400)
			expect(fired).toEqual({ "delete" })
			expect(w.ra._isOpen()).toBe(false)
			expect(w.ra.dump().phase).toBe("closed")
		end
	)

	it("Cancel (gamepad ButtonB) closes the menu without firing anything, and restores focus", function()
		local fired: { string } = {}
		local w = keyboardWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = focusableBody("Body"),
				trailing = {
					{
						id = "flag",
						role = "normal",
						label = "Flag",
						onAction = function()
							table.insert(fired, "flag")
						end,
					},
				},
			})
		end)
		w.pres.focus.focusOn("/S/Row/Content/Body")
		w.press("ButtonX")
		w.pres.refresh()
		expect(w.ra.dump().menuOpen).toBe(true)
		w.press("ButtonB")
		w.pres.refresh()
		expect(#fired).toBe(0)
		expect(w.ra.dump().menuOpen).toBe(false)
		expect(w.pres.focus.focused:get()).toBe("/S/Row/Content/Body") -- restored to the pre-open focus
	end)

	it("menu traps focus while open (transientScope): Navigate cannot escape into content or a sibling", function()
		local w = keyboardWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = focusableBody("Body"),
				leading = {
					{ id = "flag", role = "normal", label = "Flag", onAction = function() end },
				},
				trailing = {
					{ id = "delete", role = "destructive", label = "Delete", onAction = function() end },
				},
			})
		end)
		w.pres.focus.focusOn("/S/Row/Content/Body")
		w.press("ButtonX")
		w.pres.refresh()
		local menuRoot = "/RowActionsMenu-Row/Menu/MenuRows"
		local landed = w.pres.focus.focused:get() :: string
		expect(string.sub(landed, 1, #menuRoot)).toBe(menuRoot)
		for _ = 1, 6 do
			w.press("Down")
		end
		local afterNav = w.pres.focus.focused:get() :: string
		expect(string.sub(afterNav, 1, #menuRoot)).toBe(menuRoot) -- never escaped
		expect(afterNav).never().toBe("/S/Row/Content/Body")
	end)

	it("toggling the menu 10 times leaks nothing", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local baseline = core:counters()

		local ra = row_actions.build(LuauUI, core, {
			id = "Row",
			content = focusableBody("Body"),
			trailing = {
				{ id = "delete", role = "destructive", label = "Delete", onAction = function() end },
				{ id = "flag", role = "normal", label = "Flag", onAction = function() end },
			},
		})
		local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } })
		local handle = pres.present(screen, { sinkNavigation = true })
		pres.refresh()
		pres.focus.focusOn("/S/Row/Content/Body")

		for _ = 1, 10 do
			system.deviceKey("ButtonX", true) -- open
			system.deviceKey("ButtonX", false)
			pres.refresh()
			system.deviceKey("ButtonX", true) -- close (toggle)
			system.deviceKey("ButtonX", false)
			pres.refresh()
		end
		expect(ra.dump().menuOpen).toBe(false)

		pres.dismiss(handle)
		ra.dispose()

		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)

	-- REVIEW ROUND 1, MAJOR (reproduced deterministically): Delete used to
	-- reach `commitDestructive` through the keys context's OWN, separate IAS
	-- path regardless of the open menu — `pathInsideRow` is a whole-row
	-- scope (content, tray, OR an open menu row are all "inside"), so with
	-- the menu open and a NON-destructive row focused ("Flag"), Delete still
	-- fired the destructive action straight through, collapsing the row
	-- (`phase == "closed"`) while `menuOpen` stayed `true` and the menu's
	-- own rows stayed mounted on top of it. Fixed: Delete is inert for the
	-- whole time the menu is open (the menu owns all input then); this is
	-- exactly the brief's own regression recipe.
	it("Delete while the menu is open does not bypass it — the open menu owns input", function()
		local fired: { string } = {}
		local w = keyboardWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = focusableBody("Body"),
				trailing = {
					{
						id = "flag",
						role = "normal",
						label = "Flag",
						onAction = function()
							table.insert(fired, "flag")
						end,
					},
					{
						id = "delete",
						role = "destructive",
						label = "Delete",
						onAction = function()
							table.insert(fired, "delete")
						end,
					},
				},
			})
		end)
		w.pres.focus.focusOn("/S/Row/Content/Body")
		w.press("ButtonX") -- open the menu; focus enters on its first (non-destructive) row
		w.pres.refresh()
		expect(w.ra.dump().menuOpen).toBe(true)
		expect(w.pres.focus.focused:get()).toBe("/RowActionsMenu-Row/Menu/MenuRows/Action:flag")

		w.press("Delete") -- must be INERT: the menu owns input, not this key
		w.settle(60)
		expect(#fired).toBe(0)
		expect(w.ra.dump().menuOpen).toBe(true) -- still open
		expect(w.ra.dump().phase).toBe("closed") -- the tray never opened, let alone collapsed
		-- FUNCTIONAL, not just un-fired: focus is still exactly where it was
		-- (Delete did not disturb the menu's own mount/focus state), and the
		-- menu's own Activate still works normally.
		expect(w.pres.focus.focused:get()).toBe("/RowActionsMenu-Row/Menu/MenuRows/Action:flag")
		expect(w.adapter.node("/RowActionsMenu-Row/Menu/MenuRows/Action:flag")).never().toBe(nil)

		w.press("ButtonB") -- Cancel closes without firing
		w.pres.refresh()
		expect(w.ra.dump().menuOpen).toBe(false)
		expect(#fired).toBe(0)
		expect(w.pres.focus.focused:get()).toBe("/S/Row/Content/Body") -- restored

		-- THEN: Delete on the focused row content commits normally (the
		-- guard only blocks Delete while the menu is actually open).
		w.press("Delete")
		w.settle(400)
		expect(fired).toEqual({ "delete" })
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().phase).toBe("closed")
	end)

	-- REDTEAM ITEM 7 (MAJOR, same-row half): the ORIGINAL menu-open
	-- carve-out (see the test above) only ever gated the KEYBOARD Delete
	-- entry point — a full-swipe POINTER gesture committing on this SAME
	-- row was never gated at all, stranding the menu (and its
	-- `transientScope` focus trap) on top of a row that had just slid off
	-- and collapsed out from under it.
	it("a full-swipe commit under an OPEN MENU on the SAME row closes the menu first, not stranding it", function()
		local fired: { string } = {}
		local w = keyboardWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = focusableBody("Body"),
				trailing = {
					{
						id = "delete",
						role = "destructive",
						label = "Delete",
						onAction = function()
							table.insert(fired, "delete")
						end,
					},
				},
			})
		end)
		w.pres.focus.focusOn("/S/Row/Content/Body")
		w.press("ButtonX")
		w.pres.refresh()
		expect(w.ra.dump().menuOpen).toBe(true)

		local rowWidth = rowWidthOf(w)
		w.adapter.pointerDown(HIT, 0, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(-15, 20) -- past the lock
		w.tick(1.0)
		local releaseX = -(rowWidth * 0.7) -- past the 60% full-swipe commit threshold
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		-- the menu closes IMMEDIATELY, synchronously with the commit
		-- starting — not merely "eventually" once the whole slide+collapse
		-- chain finishes several frames later.
		expect(w.ra.dump().menuOpen).toBe(false)
		w.settle(600)
		expect(fired).toEqual({ "delete" })
		expect(w.ra._isOpen()).toBe(false)
		expect(w.adapter.node("/RowActionsMenu-Row/Menu/MenuRows")).toBe(nil) -- unmounted, not stranded
	end)

	it(
		"two rows on one screen: focusing row A and pressing Delete commits only A (the scope actually gates, not merely exists)",
		function()
			local firedA: { string } = {}
			local firedB: { string } = {}
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
			local function trailingRow(rowId: string, fired: { string })
				return row_actions.build(LuauUI, core, {
					id = rowId,
					content = focusableBody("Body"),
					trailing = {
						{
							id = "delete",
							role = "destructive",
							label = "Delete",
							onAction = function()
								table.insert(fired, "delete")
							end,
						},
					},
				})
			end
			local rowA = trailingRow("RowA", firedA)
			local rowB = trailingRow("RowB", firedB)
			local screen = LuauUI.UI.Screen({ id = "S", children = { rowA.blueprint, rowB.blueprint } })
			pres.present(screen, { sinkNavigation = true })
			pres.refresh()
			pres.focus.focusOn("/S/RowA/Content/Body")
			system.deviceKey("Delete", true)
			system.deviceKey("Delete", false)
			pres.refresh()
			for _ = 1, 400 do
				clockTime += ROW_ACTIONS_KEY_FRAME
				pres.tick(ROW_ACTIONS_KEY_FRAME)
				pres.refresh()
			end
			expect(firedA).toEqual({ "delete" })
			expect(#firedB).toBe(0) -- B's own Delete binding never saw it: focus never entered B's scope
		end
	)

	it(
		"popup parity: a tap OUTSIDE the open menu on a sibling closes the menu AND swallows the press (opposite of the tray's own no-swallow)",
		function()
			local menuFired: { string } = {}
			local siblingFired: { string } = {}
			local core = LuauUI.newCore()
			local env = LuauUI.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
			local system = LuauUI.newActionSystem(core)
			local adapter = fake_target.new()
			local pres = LuauUI.newPresenter(core, env, adapter, system)
			local ra = row_actions.build(LuauUI, core, {
				id = "Row",
				content = focusableBody("Body"),
				trailing = {
					{
						id = "flag",
						role = "normal",
						label = "Flag",
						onAction = function()
							table.insert(menuFired, "flag")
						end,
					},
				},
			})
			local sibling = LuauUI.UI.Button({
				id = "Sibling",
				label = "Sibling",
				width = { type = "fixed", px = 200 },
				height = { type = "fixed", px = 48 },
				onActivate = function()
					table.insert(siblingFired, "tap")
				end,
			})
			local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint, sibling } })
			pres.present(screen, { sinkNavigation = true })
			pres.refresh()
			pres.focus.focusOn("/S/Row/Content/Body")
			system.deviceKey("ButtonX", true)
			system.deviceKey("ButtonX", false)
			pres.refresh()
			expect(ra.dump().menuOpen).toBe(true)
			adapter.tap("/S/Sibling")
			pres.refresh()
			expect(ra.dump().menuOpen).toBe(false) -- closed
			expect(#siblingFired).toBe(0) -- SWALLOWED — the menu behaves like PopupButton, not like the tray
			expect(#menuFired).toBe(0) -- nothing in the row's own menu fired either
		end
	)

	-- REVIEW ROUND 1, item 3: menu rows are `width = fill` + a THEME-fixed
	-- `height`, carrying a player-facing label, with zero pseudo-loc coverage
	-- before this test. Pinned rather than re-engineered (see the Task 8 fix
	-- report for the analysis): unlike the tray — a fixed-height HStack
	-- whose buttons are forced to a shared row height AND must not grow it,
	-- so Task 2-4 derive each button's WIDTH from its measured natural size
	-- — a menu row is `fill` INSIDE A CONTENT-SIZED (hugging) parent (the
	-- `Menu` Anchor and `MenuRows` VStack both go unconstrained-width,
	-- exactly `popup_button.luau`'s own `Popup`/rows shape when NOT given an
	-- explicit fill width by an outer composite). A `fill` child of a
	-- hugging parent reports its own NATURAL width — proven live below —
	-- so nothing here ever forces a wrap: the row widens to the label
	-- instead, the same escape hatch the tray's buttons use on the other
	-- axis. `controlSizes.compact.height` (36px @ default theme) is a
	-- comfortable single-line floor for the compact control type ladder,
	-- and every existing control that uses it (PopupButton, Table headers)
	-- carries the identical assumption — this is inherited, not new.
	it(
		"menu row labels survive 1.4x pseudo-loc without wrapping or clipping (fill-inside-a-hugging-parent widens instead)",
		function()
			local w = keyboardWorld(function(core)
				return row_actions.build(LuauUI, core, {
					id = "Row",
					content = focusableBody("Body"),
					trailing = {
						{ id = "delete", role = "destructive", label = lt.PSEUDO, onAction = function() end },
					},
				})
			end)
			w.pres.focus.focusOn("/S/Row/Content/Body")
			w.press("ButtonX")
			w.pres.refresh()
			local path = "/RowActionsMenu-Row/Menu/MenuRows/Action:delete"
			local node = w.adapter.node(path)
			expect(node ~= nil).toBe(true)
			expect((node :: any).props.label).toBe(lt.PSEUDO)

			-- the menu is its own presented surface now (redteam item 2's
			-- fix) — its live text facts live on ITS OWN controller, not the
			-- base screen's (`w.handle.controller` would find nothing here).
			local facts = w.ra._menuHandle().controller.textAt(path)
			expect(facts ~= nil).toBe(true)
			expect(facts.truncated).toBe(false)
			expect(facts.lines).toBe(1) -- never wraps: the row widens instead of reflowing

			-- independent proof, not just the solver's own verdict: the rect the
			-- row actually solved to is at least as wide as the label's real
			-- natural (single-line) width at its real font/size — the same
			-- oracle the tray's own pseudo-loc test uses.
			local natural = text_metrics.measure(lt.PSEUDO, facts.font, facts.size, math.huge)
			expect((node :: any).rect.w >= natural.width).toBe(true)
		end
	)

	-- ICON-FIRST IS THE TRAY'S INVERSION ONLY (director ruling, device round
	-- 2026-08-12). One action, two surfaces, opposite representations — asserted
	-- side by side in ONE world so a future edit that folds the two call sites
	-- into a shared helper cannot pass. The menu is the reading of the tray a
	-- player reaches for when a glyph is not enough, so it is where the words
	-- have to live.
	it("the same action wears its ICON in the tray and its WORD in the menu row", function()
		local w = keyboardWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = focusableBody("Body"),
				trailing = {
					{
						id = "delete",
						role = "destructive",
						label = "Delete",
						icon = "trash",
						onAction = function() end,
					},
				},
			})
		end)
		w.ra._open("trailing")
		w.pres.refresh()
		local trayButton = w.adapter.node("/S/Row/TrayTrailingWhen/then/TrayTrailing/Action:delete")
		expect(trayButton ~= nil).toBe(true)
		expect((trayButton :: any).props.label).toBe("\\_/") -- the framework glyph for `trash`

		w.pres.focus.focusOn("/S/Row/Content/Body")
		w.press("ButtonX")
		w.pres.refresh()
		local menuRow = w.adapter.node("/RowActionsMenu-Row/Menu/MenuRows/Action:delete")
		expect(menuRow ~= nil).toBe(true)
		expect((menuRow :: any).props.label).toBe("Delete")
	end)
end)

-- Task 8b: the keyboard half of the action menu, now expressible via
-- `src/input/actions.luau`'s additive `modifiers` slot (see its own spec,
-- tests/input.spec.luau "input: modifier-gated bindings (Task 8b)", for the
-- action-system-level preemption proof this control-level suite builds on).
-- `RowActionsMenu` binds `Return` with `modifiers = { shift = true }` in the
-- SAME sink=true, priority-10000 context ButtonX/Delete already use.
describe("RowActions Task 8b: the action menu (Shift+Return)", function()
	it("Shift+Return opens the menu, entering focus on its first row — identical outcome to ButtonX", function()
		local fired: { string } = {}
		local w = keyboardWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = focusableBody("Body"),
				trailing = {
					{
						id = "flag",
						role = "normal",
						label = "Flag",
						onAction = function()
							table.insert(fired, "flag")
						end,
					},
				},
			})
		end)
		w.pres.focus.focusOn("/S/Row/Content/Body")
		w.pressShiftReturn()
		w.pres.refresh()
		expect(w.ra.dump().menuOpen).toBe(true)
		expect(w.pres.focus.focused:get()).toBe("/RowActionsMenu-Row/Menu/MenuRows/Action:flag")
		-- plain Return now activates the focused MENU row (the menu's own
		-- contribution, not the Shift-gated binding) — same as the ButtonX
		-- describe block above proves; re-asserted here to confirm the
		-- keyboard entry point hands off into the SAME shipped machinery.
		w.press("Return")
		w.pres.refresh()
		expect(fired).toEqual({ "flag" })
		expect(w.ra.dump().menuOpen).toBe(false)
	end)

	it("Shift+Return while the menu is open closes it (toggle, no distinct close key needed)", function()
		local w = keyboardWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = focusableBody("Body"),
				trailing = {
					{ id = "flag", role = "normal", label = "Flag", onAction = function() end },
				},
			})
		end)
		w.pres.focus.focusOn("/S/Row/Content/Body")
		w.pressShiftReturn()
		w.pres.refresh()
		expect(w.ra.dump().menuOpen).toBe(true)
		w.pressShiftReturn()
		w.pres.refresh()
		expect(w.ra.dump().menuOpen).toBe(false)
		expect(w.pres.focus.focused:get()).toBe("/S/Row/Content/Body") -- restored, same as ButtonX/Cancel
	end)

	-- THE REGRESSION TEST THIS TASK EXISTS FOR (design constraint: "while
	-- Shift is held, Shift+Return must fire ONLY the modified binding — the
	-- screen's plain-Return Activate must NOT also fire"). `focusableBody`
	-- carries its own `onActivate` — exactly the shape the Task 8 report
	-- identified as the realistic double-fire hazard (a second Return-bound
	-- context that does not sink would deliver alongside Activate on every
	-- shifted press). Both counters must be examined: the menu opening
	-- ALONE is not proof the row's own Activate stayed silent.
	it(
		"Shift+Return fires ONLY the menu toggle — the row content's own onActivate does not also fire (no double-fire)",
		function()
			local activated: { string } = {}
			local w = keyboardWorld(function(core)
				return row_actions.build(LuauUI, core, {
					id = "Row",
					content = focusableBody("Body", activated),
					trailing = {
						{ id = "flag", role = "normal", label = "Flag", onAction = function() end },
					},
				})
			end)
			w.pres.focus.focusOn("/S/Row/Content/Body")
			w.pressShiftReturn()
			w.pres.refresh()
			expect(w.ra.dump().menuOpen).toBe(true) -- the menu toggle fired…
			expect(activated).toEqual({}) -- …and ONLY the menu toggle
		end
	)

	-- THE OTHER HALF OF THE SAME REGRESSION: plain (unshifted) Return on
	-- focused row content must keep working exactly as it did before Task
	-- 8b — the naive "sink to avoid double-fire" alternative the report
	-- rejected would have broken this instead.
	it("plain Return still activates the focused row content normally — byte-identical to before Task 8b", function()
		local activated: { string } = {}
		local w = keyboardWorld(function(core)
			return row_actions.build(LuauUI, core, {
				id = "Row",
				content = focusableBody("Body", activated),
				trailing = {
					{ id = "flag", role = "normal", label = "Flag", onAction = function() end },
				},
			})
		end)
		w.pres.focus.focusOn("/S/Row/Content/Body")
		w.press("Return")
		w.pres.refresh()
		expect(activated).toEqual({ "activate" })
		expect(w.ra.dump().menuOpen).toBe(false) -- the menu never even considered it
	end)

	-- MAJOR-1 fix round 2 (platform review, control-level regression — the
	-- action-system spec above pins the same bug at the binding layer; this
	-- pins the player-visible outcome). Reproduced against the fix-round-1
	-- commit via task-8b-review-findings.md's repro2.luau before this fix:
	-- holding plain Return, tapping Shift mid-hold, then releasing Return
	-- left the row's own `activated` stuck at 1 forever — the NEXT plain
	-- Return press was silently swallowed.
	it(
		"holding plain Return, tapping shift mid-hold, then releasing it does not swallow the NEXT plain Return activation",
		function()
			local activated: { string } = {}
			local w = keyboardWorld(function(core)
				return row_actions.build(LuauUI, core, {
					id = "Row",
					content = focusableBody("Body", activated),
					trailing = {
						{ id = "flag", role = "normal", label = "Flag", onAction = function() end },
					},
				})
			end)
			w.pres.focus.focusOn("/S/Row/Content/Body")
			w.system.deviceKey("Return", true)
			w.pres.refresh()
			w.system.deviceKey("LeftShift", true) -- shift tapped WHILE Return is still held
			w.system.deviceKey("Return", false)
			w.system.deviceKey("LeftShift", false)
			w.pres.refresh()
			expect(activated).toEqual({ "activate" }) -- the chord itself still activates once
			w.press("Return") -- the NEXT plain press — must not be swallowed
			w.pres.refresh()
			expect(activated).toEqual({ "activate", "activate" })
			expect(w.ra.dump().menuOpen).toBe(false)
		end
	)

	it(
		"Delete while the menu is open (opened via Shift+Return) stays inert — same carve-out as the ButtonX path",
		function()
			local fired: { string } = {}
			local w = keyboardWorld(function(core)
				return row_actions.build(LuauUI, core, {
					id = "Row",
					content = focusableBody("Body"),
					trailing = {
						{
							id = "delete",
							role = "destructive",
							label = "Delete",
							onAction = function()
								table.insert(fired, "delete")
							end,
						},
						{ id = "flag", role = "normal", label = "Flag", onAction = function() end },
					},
				})
			end)
			w.pres.focus.focusOn("/S/Row/Content/Body")
			w.pressShiftReturn() -- open via the NEW keyboard path
			w.pres.refresh()
			expect(w.ra.dump().menuOpen).toBe(true)
			w.press("Delete") -- must be INERT: the menu owns input, not this key
			w.pres.refresh()
			expect(w.ra.dump().menuOpen).toBe(true) -- still open
			expect(#fired).toBe(0)
		end
	)

	it(
		"opening via Shift+Return and closing via ButtonX (and vice versa) both work — one action, two bindings",
		function()
			local w = keyboardWorld(function(core)
				return row_actions.build(LuauUI, core, {
					id = "Row",
					content = focusableBody("Body"),
					trailing = {
						{ id = "flag", role = "normal", label = "Flag", onAction = function() end },
					},
				})
			end)
			w.pres.focus.focusOn("/S/Row/Content/Body")
			w.pressShiftReturn() -- open via keyboard
			w.pres.refresh()
			expect(w.ra.dump().menuOpen).toBe(true)
			w.press("ButtonX") -- close via gamepad
			w.pres.refresh()
			expect(w.ra.dump().menuOpen).toBe(false)
			w.press("ButtonX") -- open via gamepad
			w.pres.refresh()
			expect(w.ra.dump().menuOpen).toBe(true)
			w.pressShiftReturn() -- close via keyboard
			w.pres.refresh()
			expect(w.ra.dump().menuOpen).toBe(false)
		end
	)
end)

-- ===== REDTEAM ITEM 2 (BLOCKER): the menu must contribute ZERO to row/list
-- measure. Director's own regression test: the red team's exact repro
-- numbers (a row's own solved height inflating 48px -> 73px when its menu
-- opened, pushing every following row down) turned into an assertion, both
-- as a hand-built VStack list here and against a real Table
-- (`tests/table.spec.luau`'s "Table: row actions (Task 10)" describe block,
-- whose own rowHeight is authored ARITHMETICALLY — the exact shape the old
-- design could never satisfy, per redteam-fixwave-report.md item 2's own
-- investigation). Before this fix, BOTH of these fail: the VStack variant
-- because a menu-open row's own Anchor grew past its content's height, the
-- Table variant because Table hands each row an explicit `{ type = "fixed",
-- px = rowHeight }` a measured-child menu could never observe. Fixed by
-- re-homing the menu onto its own `presentModal` surface — see the big
-- comment above `local function openMenu` (row_actions.luau) for the design.
describe("RowActions redteam item 2: the menu contributes zero to row/list measure", function()
	it("opening row A's menu leaves row B's solved rect (y, x, height) byte-identical — VStack list", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)

		-- THREE actions (leading + two trailing), not one (re-review finding,
		-- MAJOR): a single-action menu is ONE row at the theme's compact
		-- control height (~36px) — SHORTER than the row's own 48px content —
		-- so under the OLD (buggy, measured-child) design the Anchor's own
		-- union-bbox height was `max(48, 36) = 48` either way and this test
		-- passed WITHOUT the fix (it never actually bit). Three menu rows
		-- (leading-then-trailing document order: archive, flag, delete)
		-- comfortably exceed 48px, reproducing the red team's own repro
		-- shape (48px content vs. a taller menu) so the assertions below
		-- fail for real against the pre-fix code. Proved directly: source
		-- reverted to 0c43f1b with tests at HEAD -> this test fails;
		-- restored -> passes (redteam-fixwave-report.md item 2's own
		-- bite-proof section has the exact transcript).
		local rowA = row_actions.build(LuauUI, core, {
			id = "RowA",
			content = focusableBody("Body"),
			leading = {
				{ id = "archive", role = "normal", label = "Archive", onAction = function() end },
			},
			trailing = {
				{ id = "flag", role = "normal", label = "Flag", onAction = function() end },
				{ id = "delete", role = "destructive", label = "Delete", onAction = function() end },
			},
		})
		-- a plain sibling leaf (not itself wrapped in row_actions — the
		-- point is only to observe whether ANYTHING moves under row A, not
		-- to exercise a second row's own actions).
		local rowB = LuauUI.UI.Text({
			id = "RowB",
			text = "Row B",
			width = { type = "fixed", px = 400 },
			height = { type = "fixed", px = 48 },
		})
		local list = LuauUI.UI.VStack({ id = "List", children = { rowA.blueprint, rowB } })
		local screen = LuauUI.UI.Screen({ id = "S", children = { list } })
		local handle = pres.present(screen, { sinkNavigation = true })
		pres.refresh()

		local pathB = "/S/List/RowB"
		local before = (adapter.node(pathB) :: any).rect

		pres.focus.focusOn("/S/List/RowA/Content/Body")
		system.deviceKey("ButtonX", true)
		system.deviceKey("ButtonX", false)
		pres.refresh()
		expect(rowA.dump().menuOpen).toBe(true) -- the menu really opened, not a no-op

		local after = (adapter.node(pathB) :: any).rect
		expect(after.y).toBe(before.y)
		expect(after.x).toBe(before.x)
		expect(after.h).toBe(before.h)

		rowA.dispose()
		pres.dismiss(handle)
	end)

	it("wrapper dispose while its menu is open dismisses the menu's own surface too — no leak", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local baseline = core:counters()

		local ra = row_actions.build(LuauUI, core, {
			id = "Row",
			content = focusableBody("Body"),
			trailing = {
				{ id = "flag", role = "normal", label = "Flag", onAction = function() end },
			},
		})
		local screen = LuauUI.UI.Screen({ id = "S", children = { ra.blueprint } })
		local handle = pres.present(screen, { sinkNavigation = true })
		pres.refresh()
		pres.focus.focusOn("/S/Row/Content/Body")

		system.deviceKey("ButtonX", true)
		system.deviceKey("ButtonX", false)
		pres.refresh()
		expect(ra.dump().menuOpen).toBe(true)
		local menuPath = "/RowActionsMenu-Row/Menu/MenuRows/Action:flag"
		expect(adapter.node(menuPath) ~= nil).toBe(true)

		ra.dispose()
		pres.refresh()
		expect(adapter.node(menuPath)).toBe(nil) -- the menu's surface tore down too, not stranded

		pres.dismiss(handle)

		local after = core:counters()
		for key, v in baseline :: { [string]: number } do
			expect((after :: any)[key]).toBe(v)
		end
	end)
end)

-- ===== Task 10: row_actions.composeWithReorder, in isolation ================
-- No mounting, no presenter, no adapter — a pure unit test of the dispatcher
-- itself (the brief's own ask: "tested in isolation"), against plain spy
-- handler tables recording every call. table.luau's own integration proof
-- (through the REAL adapter capture) lives in tests/table.spec.luau.
describe("row_actions.composeWithReorder (Task 10)", function()
	local row_actions_state = require("../src/input/row_actions_state")
	local LOCK = row_actions_state.AXIS_LOCK_PX

	-- a fake `rectOf` — every real handler this file forwards to ignores it
	-- past its own signature, and this dispatcher never reads it itself.
	local function rectOf(_path: string): any
		return nil
	end

	local function spy()
		local calls = { down = {}, move = {}, up = {}, cancel = {} }
		local handlers = {
			onPointerDown = function(path: string, pos: any, _rectOf: any): boolean?
				table.insert(calls.down, { path = path, pos = pos })
				return true
			end,
			onPointerMove = function(path: string, pos: any, _rectOf: any)
				table.insert(calls.move, { path = path, pos = pos })
			end,
			onPointerUp = function(path: string, pos: any, _rectOf: any)
				table.insert(calls.up, { path = path, pos = pos })
			end,
			onPointerCancel = function(path: string, reason: string?): boolean?
				table.insert(calls.cancel, { path = path, reason = reason })
				return nil
			end,
		}
		return handlers, calls
	end

	it("no reorderHandlers: returns rowActionsHandlers unchanged (pass-through, zero overhead)", function()
		local rowActionsHandlers = spy()
		local composed = row_actions.composeWithReorder(rowActionsHandlers, nil)
		expect(composed == rowActionsHandlers).toBe(true)
	end)

	it(
		"touch: routed to rowActions from onPointerDown, every subsequent event too — reorder never sees it",
		function()
			local raHandlers, raCalls = spy()
			local reorderHandlers, reorderCalls = spy()
			local composed = row_actions.composeWithReorder(raHandlers, reorderHandlers)
			local accepted = composed.onPointerDown("/S/Row/Hit", { x = 10, y = 10, pointerType = "touch" }, rectOf)
			expect(accepted).toBe(true)
			expect(#raCalls.down).toBe(1)
			composed.onPointerMove("/S/Row/Hit", { x = 40, y = 10, pointerType = "touch" }, rectOf) -- huge dx, still touch
			composed.onPointerUp("/S/Row/Hit", { x = 40, y = 10, pointerType = "touch" }, rectOf)
			expect(#raCalls.move).toBe(1)
			expect(#raCalls.up).toBe(1)
			expect(#reorderCalls.down).toBe(0)
			expect(#reorderCalls.move).toBe(0)
			expect(#reorderCalls.up).toBe(0)
		end
	)

	it(
		"mouse vertical: replays the down at the ORIGIN into reorder; rowActions never sees this gesture at all",
		function()
			local raHandlers, raCalls = spy()
			local reorderHandlers, reorderCalls = spy()
			local composed = row_actions.composeWithReorder(raHandlers, reorderHandlers)
			local accepted = composed.onPointerDown("/S/Row/Hit", { x = 100, y = 20, pointerType = "mouse" }, rectOf)
			expect(accepted).toBe(true) -- tentative accept; axis unknown yet
			expect(#raCalls.down).toBe(0)
			expect(#reorderCalls.down).toBe(0) -- deferred: neither engine told yet
			-- dy = LOCK + 4, dx = 1: past the lock radius, |dy| > |dx| -> vertical
			composed.onPointerMove("/S/Row/Hit", { x = 101, y = 20 + LOCK + 4, pointerType = "mouse" }, rectOf)
			expect(#reorderCalls.down).toBe(1)
			-- REPLAYED AT THE ORIGIN, not the current move position
			expect(reorderCalls.down[1].pos.x).toBe(100)
			expect(reorderCalls.down[1].pos.y).toBe(20)
			expect(#raCalls.down).toBe(0) -- rowActions never entered this gesture
			-- the SAME move that resolved the axis also delivers itself (row_actions'
			-- own internal onPointerMove does the identical "resolve, then fall
			-- through and act on this move too" — see its own onPointerMove)
			expect(#reorderCalls.move).toBe(1)
			expect(reorderCalls.move[1].pos.y).toBe(20 + LOCK + 4)
			composed.onPointerMove("/S/Row/Hit", { x = 102, y = 20 + LOCK + 10, pointerType = "mouse" }, rectOf)
			expect(#reorderCalls.move).toBe(2)
			expect(reorderCalls.move[2].pos.y).toBe(20 + LOCK + 10) -- live position, not replayed
			composed.onPointerUp("/S/Row/Hit", { x = 102, y = 20 + LOCK + 10, pointerType = "mouse" }, rectOf)
			expect(#reorderCalls.up).toBe(1)
			expect(#raCalls.move).toBe(0)
			expect(#raCalls.up).toBe(0)
		end
	)

	it("mouse horizontal: rowActions owns the gesture; reorder's rowDrag is never seeded", function()
		local raHandlers, raCalls = spy()
		local reorderHandlers, reorderCalls = spy()
		local composed = row_actions.composeWithReorder(raHandlers, reorderHandlers)
		composed.onPointerDown("/S/Row/Hit", { x = 100, y = 20, pointerType = "mouse" }, rectOf)
		-- dx = LOCK + 6, dy = 1: past the lock radius, |dx| > |dy| -> horizontal
		composed.onPointerMove("/S/Row/Hit", { x = 100 + LOCK + 6, y = 21, pointerType = "mouse" }, rectOf)
		expect(#raCalls.down).toBe(1)
		expect(raCalls.down[1].pos.x).toBe(100) -- replayed at the origin
		expect(raCalls.down[1].pos.y).toBe(20)
		expect(#reorderCalls.down).toBe(0)
		expect(#raCalls.move).toBe(1) -- the resolving move also delivers itself
		composed.onPointerMove("/S/Row/Hit", { x = 100 + LOCK + 20, y = 22, pointerType = "mouse" }, rectOf)
		expect(#raCalls.move).toBe(2)
		composed.onPointerUp("/S/Row/Hit", { x = 100 + LOCK + 20, y = 22, pointerType = "mouse" }, rectOf)
		expect(#raCalls.up).toBe(1)
		expect(#reorderCalls.move).toBe(0)
		expect(#reorderCalls.up).toBe(0)
	end)

	it("ties go vertical, matching row_actions_state.axisVerdict's own rule", function()
		local raHandlers, raCalls = spy()
		local reorderHandlers, reorderCalls = spy()
		local composed = row_actions.composeWithReorder(raHandlers, reorderHandlers)
		composed.onPointerDown("/S/Row/Hit", { x = 0, y = 0, pointerType = "mouse" }, rectOf)
		-- |dx| == |dy|, both past the lock radius: axisVerdict resolves vertical
		composed.onPointerMove("/S/Row/Hit", { x = LOCK + 6, y = LOCK + 6, pointerType = "mouse" }, rectOf)
		expect(#reorderCalls.down).toBe(1)
		expect(#raCalls.down).toBe(0)
	end)

	it("a tap that never crosses the lock radius calls neither engine's down, and up is a no-op for both", function()
		local raHandlers, raCalls = spy()
		local reorderHandlers, reorderCalls = spy()
		local composed = row_actions.composeWithReorder(raHandlers, reorderHandlers)
		composed.onPointerDown("/S/Row/Hit", { x = 50, y = 50, pointerType = "mouse" }, rectOf)
		composed.onPointerMove("/S/Row/Hit", { x = 51, y = 51, pointerType = "mouse" }, rectOf) -- inside the lock radius
		composed.onPointerUp("/S/Row/Hit", { x = 51, y = 51, pointerType = "mouse" }, rectOf)
		expect(#raCalls.down).toBe(0)
		expect(#raCalls.up).toBe(0)
		expect(#reorderCalls.down).toBe(0)
		expect(#reorderCalls.up).toBe(0)
	end)

	it("cancel mid-vertical-drag forwards to reorder's own onPointerCancel only", function()
		local raHandlers, raCalls = spy()
		local reorderHandlers, reorderCalls = spy()
		local composed = row_actions.composeWithReorder(raHandlers, reorderHandlers)
		composed.onPointerDown("/S/Row/Hit", { x = 0, y = 0, pointerType = "mouse" }, rectOf)
		composed.onPointerMove("/S/Row/Hit", { x = 1, y = LOCK + 5, pointerType = "mouse" }, rectOf)
		expect(#reorderCalls.down).toBe(1)
		expect(#reorderCalls.move).toBe(1) -- the resolving move also delivers itself
		composed.onPointerCancel("/S/Row/Hit", "interrupted")
		expect(#reorderCalls.cancel).toBe(1)
		expect(reorderCalls.cancel[1].reason).toBe("interrupted")
		expect(#raCalls.cancel).toBe(0)
		-- cancel clears the pending gesture: a further move/up is a no-op
		composed.onPointerMove("/S/Row/Hit", { x = 1, y = LOCK + 20, pointerType = "mouse" }, rectOf)
		expect(#reorderCalls.move).toBe(1) -- unchanged
	end)

	it("a second down while one is pending declines (never steals a live capture)", function()
		local raHandlers = spy()
		local reorderHandlers = spy()
		local composed = row_actions.composeWithReorder(raHandlers, reorderHandlers)
		expect(composed.onPointerDown("/S/Row/Hit", { x = 0, y = 0, pointerType = "mouse" }, rectOf)).toBe(true)
		expect(composed.onPointerDown("/S/Row/Hit", { x = 5, y = 5, pointerType = "mouse" }, rectOf)).toBe(false)
	end)

	-- REDTEAM ITEM 13 (LOW): the composed path REPLAYS the down at the true
	-- origin POSITION but at the LOCK-CROSSING moment (composeWithReorder
	-- has no clock of its own — deliberately, matching row_actions_state.
	-- luau's own purity). The mislabeled-time origin sample used to sit in
	-- the velocity tracker's own 100ms retention window right alongside the
	-- flick's real recent samples (all pushed within milliseconds of the
	-- lock crossing, by definition — the window's own staleness eviction
	-- never fires on it), so "first vs last across the window" paired a
	-- DISTANCE spanning the WHOLE real gesture (true origin to release)
	-- against a TIME spanning only the tiny post-lock portion — an inflated
	-- velocity a direct (uncomposed) gesture, whose true-origin sample is
	-- correctly timestamped and gets evicted once real time has actually
	-- passed, can never produce.
	--
	-- Repro (confirmed live before writing the fix): a slow, real 1.0s
	-- creep near (never crossing) the axis lock, then a fast two-frame
	-- flick whose RAW release distance alone sits safely under the
	-- full-swipe commit threshold (60% of row width) — with the bug, the
	-- composed path's inflated velocity pushed the settle() projection over
	-- that threshold and COMMITTED (fired the destructive action, collapsed
	-- the row) for a gesture the DIRECT path — and a player's actual
	-- finger — only ever opened.
	local function stubReorderHandlers()
		return {
			onPointerDown = function()
				return true
			end,
			onPointerMove = function() end,
			onPointerUp = function() end,
			onPointerCancel = function()
				return nil
			end,
		}
	end
	local function rectOf13(_path: string): any
		return nil
	end
	local function driveFlick13(handlers: any, w: any)
		handlers.onPointerDown(HIT, { x = 100, y = 20, pointerType = "mouse" }, rectOf13)
		w.tick(0.3)
		handlers.onPointerMove(HIT, { x = 103, y = 20 }, rectOf13) -- dx=3: still pending
		w.tick(0.3)
		handlers.onPointerMove(HIT, { x = 105, y = 20 }, rectOf13) -- dx=5: still pending
		w.tick(0.4) -- 1.0s of real creep before the lock is ever crossed
		handlers.onPointerMove(HIT, { x = 0, y = 20 }, rectOf13) -- crosses the lock, one move
		w.tick(FRAME)
		handlers.onPointerMove(HIT, { x = -20, y = 20 }, rectOf13) -- continuing the same flick
		w.tick(FRAME)
		handlers.onPointerUp(HIT, { x = -20, y = 20 }, rectOf13)
	end

	it(
		"a slow creep then a two-frame flick settles the SAME way (open, not commit) through the composed path as the direct path",
		function()
			local direct = trailingWorld()
			driveFlick13(direct.ra._pointerHandlers, direct)
			-- the raw release position alone (mag 120, well under 60% of the
			-- 400px row) can never commit on distance alone — only an inflated
			-- velocity could push this over
			expect(direct.ra.dump().offset).toBe(-120)
			direct.settle(400)
			expect(#direct.fired).toBe(0)
			expect(direct.ra._isOpen()).toBe(true) -- opened, not committed

			local composed = trailingWorld()
			local composedHandlers = row_actions.composeWithReorder(composed.ra._pointerHandlers, stubReorderHandlers())
			driveFlick13(composedHandlers, composed)
			expect(composed.ra.dump().offset).toBe(-120) -- position tracking is unaffected by this fix
			composed.settle(400)
			expect(#composed.fired).toBe(0) -- NOT committed — matches the direct path
			expect(composed.ra._isOpen()).toBe(true)
		end
	)
end)

-- ===========================================================================
-- FINAL FIX WAVE, item 1 (BLOCKER; .superpowers/sdd/row-actions-implementation/
-- final-review-findings.md). Director ruling (iOS/SwiftUI-faithful): a STARTED
-- destructive commit is IRREVOCABLE — it completes (slide-off, collapse, fire
-- exactly once) regardless of close()/a sibling's coordinator claim/scroll/an
-- outside tap/Cancel arriving mid-flight. `_commitFirst` starts the SAME chain
-- a full-swipe gesture's release does (`doCommit` -> `doCommitAction`) without
-- a real pointer choreography — what lets these probes reach "mid-flight,
-- nothing settled yet" deterministically, the exact window the ORIGINAL bug
-- (an orphaned `onSettle` chain surviving a `close()` that had already cleared
-- `committed` and re-aimed the spring) needed to bite.
-- ===========================================================================
describe("RowActions final fix wave (redteam item 1, BLOCKER): irrevocable commit", function()
	it(
		"probe B: close() mid-commit does not cancel — fires exactly once and the row still completes its collapse (not stuck at offset 0)",
		function()
			local rowHeightBefore = 48
			local w = trailingWorld(nil, "destructive")
			expect(w.ra._commitFirst("trailing")).toBe(true)
			expect(w.ra.dump().phase).toBe("committing")
			expect(#w.fired).toBe(0)
			-- the external cancel attempt: must be a total no-op while committing
			w.ra._close()
			expect(w.ra.dump().phase).toBe("committing") -- still committing — close() did nothing
			expect(#w.fired).toBe(0)
			local minHeight = rowHeightBefore
			for _ = 1, 400 do
				w.tick(FRAME)
				local h = w.handle.controller.rectOf(ROW).h
				if h < minHeight then
					minHeight = h
				end
			end
			expect(#w.fired).toBe(1)
			expect(w.fired[1]).toBe("delete")
			expect(minHeight).toBeCloseTo(0, 0.5) -- the collapse actually completed, not interrupted mid-flight
			expect(w.ra._isOpen()).toBe(false)
			expect(w.ra.dump().phase).toBe("closed")
		end
	)

	it("probe C: a new gesture cannot start mid-commit — pointerDown declines, exactly one fire", function()
		local w = trailingWorld(nil, "destructive")
		expect(w.ra._commitFirst("trailing")).toBe(true)
		expect(w.ra.dump().phase).toBe("committing")
		-- the exposed seam directly: onPointerDown must DECLINE (false), the
		-- same "never steal a live thing" shape as a second down mid-drag
		local accepted = w.ra._pointerHandlers.onPointerDown(HIT, { x = 0, y = 20, pointerType = "mouse" }, function()
			return nil
		end)
		expect(accepted).toBe(false)
		-- and through the real adapter: a declined down never establishes a
		-- capture, so a move/up landing afterward touch nothing at all —
		-- critically, they must NOT `spring:stop()` the in-flight offscreen
		-- slide (the deeper hazard a wrongly-accepted second gesture would
		-- cause even with `doCommitAction`'s own `committed` re-entry guard).
		w.adapter.pointerDown(HIT, 0, 20, "mouse")
		w.adapter.pointerMove(-300, 20)
		w.adapter.pointerUp(-300, 20)
		w.settle(600)
		expect(#w.fired).toBe(1) -- the ORIGINAL commit only, never a second
		expect(w.fired[1]).toBe("delete")
		expect(w.ra._isOpen()).toBe(false)
	end)

	-- a two-row world sharing one coordinator, with a REAL destructive action
	-- (unlike the Task 7 describe block's own `twoRowWorld`, whose rows carry
	-- a normal-role "delete" — irrelevant for probing an in-flight
	-- irrevocable COMMIT, which only a destructive full swipe ever starts).
	local function twoDestructiveRowWorld()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local system = LuauUI.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, system)
		local coordinator = row_actions.newCoordinator(core)
		local firedA: { string } = {}
		local firedB: { string } = {}
		local function trailingRow(rowId: string, fired: { string })
			return row_actions.build(LuauUI, core, {
				id = rowId,
				content = LuauUI.UI.Button({
					id = "Body",
					label = "Row " .. rowId,
					width = { type = "fixed", px = 400 },
					height = { type = "fixed", px = 48 },
					onActivate = function()
						table.insert(fired, "tap")
					end,
				}),
				trailing = {
					{
						id = "delete",
						label = "Delete",
						role = "destructive",
						onAction = function()
							table.insert(fired, "delete")
						end,
					},
				},
				coordinator = coordinator,
			})
		end
		local rowA = trailingRow("RowA", firedA)
		local rowB = trailingRow("RowB", firedB)
		local screen = LuauUI.UI.Screen({ id = "S", children = { rowA.blueprint, rowB.blueprint } })
		local handle = pres.present(screen, { sinkNavigation = true })
		pres.refresh()
		local w: any = {
			core = core,
			env = env,
			system = system,
			adapter = adapter,
			pres = pres,
			handle = handle,
			coordinator = coordinator,
			rowA = rowA,
			rowB = rowB,
			firedA = firedA,
			firedB = firedB,
		}
		function w.tick(dt: number)
			pres.tick(dt)
			pres.refresh()
		end
		function w.settle(frames: number?)
			for _ = 1, frames or 20 do
				w.tick(1 / 60)
			end
		end
		return w
	end

	it(
		"a sibling row starting a gesture (coordinator claim) during A's commit: A's commit completes, fires exactly once",
		function()
			local w = twoDestructiveRowWorld()
			w.rowA._open("trailing") -- claims the coordinator (this IS what `claimed` tracks)
			w.settle()
			expect(w.rowA._isOpen()).toBe(true)
			expect(w.rowA._commitFirst("trailing")).toBe(true)
			expect(w.rowA.dump().phase).toBe("committing")
			-- row B claims the coordinator (`newCoordinator.claim`'s own cross-row
			-- half — the exact site that used to call the OLD `_close()`, which
			-- used to clear `committed` and re-aim A's spring)
			w.rowB._open("trailing")
			expect(w.rowA.dump().phase).toBe("committing") -- unaffected by the sibling claim
			w.settle(600)
			expect(#w.firedA).toBe(1)
			expect(w.firedA[1]).toBe("delete")
			expect(w.rowA._isOpen()).toBe(false)
			expect(w.rowB._isOpen()).toBe(true) -- B's own open is unaffected either way
		end
	)

	it("scroll movement during A's commit: A's commit completes, fires exactly once", function()
		local w = twoDestructiveRowWorld()
		w.rowA._open("trailing") -- claims the coordinator (this IS what `claimed` tracks)
		w.settle()
		expect(w.rowA._isOpen()).toBe(true)
		expect(w.rowA._commitFirst("trailing")).toBe(true)
		expect(w.rowA.dump().phase).toBe("committing")
		local observer: ((pos: { x: number, y: number }) -> ())? = nil
		local stubController = {
			observeScroll = function(_path: string, fn: (pos: { x: number, y: number }) -> ()): () -> ()
				observer = fn
				return function()
					observer = nil
				end
			end,
		}
		local unbind = w.coordinator.bindScroll(stubController, "/S/List")
		local fireScroll = observer :: (pos: { x: number, y: number }) -> ()
		fireScroll({ x = 0, y = 5 }) -- `bindScroll`'s own no-op-on-a-no-op-claimed row IS `claimed._close()`
		expect(w.rowA.dump().phase).toBe("committing") -- unaffected by the scroll
		w.settle(600)
		expect(#w.firedA).toBe(1)
		expect(w.firedA[1]).toBe("delete")
		expect(w.rowA._isOpen()).toBe(false)
		unbind()
	end)

	it(
		"an outside tap during A's commit: A's commit completes, fires exactly once, and the tapped control still activates (round-7 no-swallow, unaffected)",
		function()
			local w = twoDestructiveRowWorld()
			expect(w.rowA._commitFirst("trailing")).toBe(true)
			expect(w.rowA.dump().phase).toBe("committing")
			expect(#w.firedB).toBe(0)
			-- a tap on row B's own button: outside row A's subtree, so it
			-- reaches A's `outsideDismiss.dismiss` (== `close`) — which must
			-- be a no-op while A is committing — and must still activate B.
			w.adapter.tap("/S/RowB/Content/Body")
			w.pres.refresh()
			expect(w.rowA.dump().phase).toBe("committing") -- unaffected by the outside tap
			expect(w.firedB).toEqual({ "tap" }) -- B's press was not swallowed
			w.settle(600)
			expect(#w.firedA).toBe(1)
			expect(w.firedA[1]).toBe("delete")
			expect(w.rowA._isOpen()).toBe(false)
		end
	)
end)

-- ===========================================================================
-- FINAL FIX WAVE, item 7 (MINOR; final-review-findings.md). The synthesized
-- popup catcher (presenter.luau's `onPopupCatcherTap`, a Zone-B empty-space
-- tap) used to swallow unconditionally regardless of `outsideDismiss.consume`
-- — correct by construction when Task 7's own investigation checked it
-- (docs: "there is nothing else at that point that could have received the
-- tap"), which is no longer true once the OWNER surface is itself PASSIVE:
-- row_actions' Table integration commonly mounts over live, un-engaged
-- gameplay (a RascalRally-shaped HUD), where empty catcher space IS
-- something else — the game underneath. Fixed by threading `consume`
-- through to the catcher and honoring it there too, WITHOUT ever engaging
-- the (possibly passive) owner as a side effect of a dismiss that pressed
-- nothing at all.
-- ===========================================================================
describe("RowActions final fix wave (redteam item 7, MINOR): passive-surface catcher consume", function()
	it(
		"outside tap on the catcher over a passive HUD: tray closes, HUD is NOT engaged, gameplay input is still delivered",
		function()
			local core = LuauUI.newCore()
			local env = LuauUI.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
			local system = LuauUI.newActionSystem(core)
			local adapter = fake_target.new()
			local pres = LuauUI.newPresenter(core, env, adapter, system)

			-- a fake gameplay stack UNDERNEATH the HUD (mirrors tests/responder.spec.luau's
			-- own `gameplay` harness): a non-sinking CharacterContext with Jump<-Space.
			local jumpCount = 0
			local char = system.createContext({ name = "CharacterContext", priority = 1000, sink = false })
			local jump = char.createAction("Jump", "Bool")
			jump.bind({ keyCode = "Space" })
			jump.onPressed(function()
				jumpCount += 1
			end)

			local fired: { string } = {}
			local ra = row_actions.build(LuauUI, core, {
				id = "Row",
				content = content("Body"),
				trailing = {
					{
						id = "delete",
						label = "Delete",
						role = "destructive",
						onAction = function()
							table.insert(fired, "delete")
						end,
					},
				},
			})
			local screen = LuauUI.UI.Screen({ id = "HUD", children = { ra.blueprint } })
			local handle = pres.present(screen, { responder = "passive" })
			pres.refresh()
			expect(handle.responder:get()).toBe("passive")

			-- reveal the tray (programmatic, not a gesture — the catcher's own
			-- outsideDismiss.active reacts to this the identical way a real swipe
			-- would)
			ra._open("trailing")
			pres.refresh()
			expect(ra._isOpen()).toBe(true)

			-- gameplay works untouched while the tray sits open, same as (a) above
			system.deviceKey("Space", true)
			system.deviceKey("Space", false)
			expect(jumpCount).toBe(1)

			local catcher = pres.topPopupCatcherPath()
			expect(catcher).never().toBeNil()
			-- (700, 550): far below the row — Zone B, empty space, same coordinate
			-- shape paradigm_popup.spec.luau's own "dismisses on a tap in EMPTY
			-- space" case uses.
			adapter.tap(catcher :: string, { x = 700, y = 550 })
			pres.refresh()

			expect(ra._isOpen()).toBe(false) -- the tray closed
			expect(#fired).toBe(0) -- a dismiss, never a commit
			-- THE FIX: the HUD must NOT have been engaged as a side effect of a
			-- dismiss that pressed nothing at all
			expect(handle.responder:get()).toBe("passive")
			expect(pres.exclusiveSurfaceActive:get()).toBe(false)
			-- ...and gameplay input is still delivered afterward (nothing sank it)
			system.deviceKey("Space", true)
			system.deviceKey("Space", false)
			expect(jumpCount).toBe(2)
		end
	)
end)
