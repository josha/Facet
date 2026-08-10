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

local ROW = "/S/Row"
local HIT = ROW .. "/Content/Hit"
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
-- override fullSwipe per test (row-actions.md's per-edge form).
local function trailingWorld(fullSwipeOpt: any?)
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

	it("full swipe commits: row slides off, collapses, onAction fires exactly once", function()
		local w = trailingWorld()
		local rowWidth = rowWidthOf(w)
		w.adapter.pointerDown(HIT, 0, 20, "mouse")
		w.tick(0.01)
		w.adapter.pointerMove(-15, 20) -- past the lock
		w.tick(1.0) -- negligible velocity: this commit is a DISTANCE commit
		local releaseX = -(rowWidth * 0.7) -- past the 60% full-swipe commit threshold
		w.adapter.pointerMove(releaseX, 20)
		w.tick(FRAME)
		w.adapter.pointerUp(releaseX, 20)
		-- three chained springs to let settle: slide off, collapse height, then
		-- close()'s own retarget-back-to-0 — generous frame budget for all three
		w.settle(400)
		expect(#w.fired).toBe(1)
		expect(w.fired[1]).toBe("delete")
		expect(w.ra._isOpen()).toBe(false)
		expect(w.ra.dump().phase).toBe("closed")
	end)

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
	it(
		"full-swipe commit reaches the OFFSCREEN target, not just the tray width (regression: syncGeometry re-aim)",
		function()
			local trayWidth = learnTrayWidth()
			local w = trailingWorld()
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
	it("dispose mid-slide-off never fires onAction and never errors; a normal commit still fires once", function()
		-- a normal commit still fires exactly once (the guard doesn't over-block)
		local normal = trailingWorld()
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
		local raced = trailingWorld()
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

	it("TOUCH: full swipe commits: row slides off, collapses, onAction fires exactly once", function()
		local w = trailingWorld()
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
			expect(w.pres.focus.focused:get()).toBe("/S/Row/Menu/MenuRowsWhen/then/MenuRows/Action:flag")
			w.press("Return") -- Activate the focused (only) menu row
			w.pres.refresh()
			expect(fired).toEqual({ "flag" })
			expect(w.ra.dump().menuOpen).toBe(false)
			expect(w.adapter.node("/S/Row/Menu/MenuRowsWhen/then/MenuRows")).toBe(nil) -- rows really unmounted
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
		expect(w.pres.focus.focused:get()).toBe("/S/Row/Menu/MenuRowsWhen/then/MenuRows/Action:archive")
		w.press("Down")
		expect(w.pres.focus.focused:get()).toBe("/S/Row/Menu/MenuRowsWhen/then/MenuRows/Action:flag")
		w.press("Down")
		expect(w.pres.focus.focused:get()).toBe("/S/Row/Menu/MenuRowsWhen/then/MenuRows/Action:delete")
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
		local menuRoot = "/S/Row/Menu/MenuRowsWhen/then/MenuRows"
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
		expect(w.pres.focus.focused:get()).toBe("/S/Row/Menu/MenuRowsWhen/then/MenuRows/Action:flag")

		w.press("Delete") -- must be INERT: the menu owns input, not this key
		w.settle(60)
		expect(#fired).toBe(0)
		expect(w.ra.dump().menuOpen).toBe(true) -- still open
		expect(w.ra.dump().phase).toBe("closed") -- the tray never opened, let alone collapsed
		-- FUNCTIONAL, not just un-fired: focus is still exactly where it was
		-- (Delete did not disturb the menu's own mount/focus state), and the
		-- menu's own Activate still works normally.
		expect(w.pres.focus.focused:get()).toBe("/S/Row/Menu/MenuRowsWhen/then/MenuRows/Action:flag")
		expect(w.adapter.node("/S/Row/Menu/MenuRowsWhen/then/MenuRows/Action:flag")).never().toBe(nil)

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
			local path = "/S/Row/Menu/MenuRowsWhen/then/MenuRows/Action:delete"
			local node = w.adapter.node(path)
			expect(node ~= nil).toBe(true)
			expect((node :: any).props.label).toBe(lt.PSEUDO)

			local facts = w.handle.controller.textAt(path)
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
		expect(w.pres.focus.focused:get()).toBe("/S/Row/Menu/MenuRowsWhen/then/MenuRows/Action:flag")
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
end)
