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

	-- extra: proves the capture-semantics decision (task-5-report.md) actually
	-- holds through the REAL adapter capture, not just by code inspection —
	-- `onPointerDown` declines any non-mouse pointerType outright, so a touch
	-- press against the SAME hit surface never captures at all.
	it("a touch press at the hit surface declines the capture (Task 6 builds real touch)", function()
		local w = trailingWorld()
		w.adapter.pointerDown(HIT, 100, 20, "touch")
		w.adapter.pointerMove(20, 20) -- would fully open on mouse; a declined capture ignores it
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
