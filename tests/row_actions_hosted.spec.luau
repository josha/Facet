--!strict
-- RowActions HOSTED MODE (row-actions perf mission, Task 2 —
-- docs/plans/row-actions-hosted-mode-design.md §"Hosted mode: a closed row
-- mounts NOTHING"). `row_actions.buildHosted` is the SAME gesture/state engine
-- `row_actions.build` runs — axis lock, live drag, flick velocity, the commit
-- ladder, the one-open coordinator — with NO blueprint at all: the host
-- (VirtualList, Task 3) owns the row's hit surface, paints the slide itself
-- (`onSlide`), drives the commit collapse (`onCommitHeight`), and builds ONE
-- shared tray overlay from `trayState`.
--
-- DRIVEN WITH BARE PATHS AND A STUB `rectOf`/controller — no mounted tree at
-- all, the precedent being the `composeWithReorder` unit tests at
-- tests/row_actions_input.spec.luau (~2400-2511). That is not a shortcut here,
-- it is the POINT: a hosted engine has no nodes of its own to mount, so the
-- only thing a test could mount would be the host's, which does not exist yet
-- (Task 3). What stands in for the presenter is exactly what a presenter
-- hands a composite: a motion clock + `now` (`bindMotion`, the seam the
-- gesture's velocity tracker asserts — src/controls/row_actions.luau's own
-- `currentNow`) and a render controller (`bindController`, the source of the
-- row's live rect and the tray buttons' text facts).
--
-- TIME IS SCRIPTED, exactly as tests/row_actions_input.spec.luau's own
-- `pointerWorld` does it: `w.tick(dt)` advances the clock the springs step on
-- AND the value `now()` returns, then runs the host's own per-frame sync.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local row_actions = require("../src/controls/row_actions")
local row_actions_state = require("../src/input/row_actions_state")
local clockLib = require("../src/motion/clock")
local themeSnapshot = require("../src/themes/snapshot")
local text_metrics = require("../src/layout/text_metrics")

-- THE HOST'S OWN PATHS (never this control's — a hosted row has no nodes of
-- its own). Shaped like what VirtualList will actually hand over: a per-row
-- Hit inside the windowed canvas, and ONE shared tray overlay for the whole
-- list (design doc §4), not a tray per row.
local ROW = "/S/List/Canvas/Row-1"
local HIT = ROW .. "/Hit"
local TRAY_TRAILING = "/S/List/Canvas/RowActionsTray/TrayTrailing"
local TRAY_LEADING = "/S/List/Canvas/RowActionsTray/TrayLeading"

local LOCK = row_actions_state.AXIS_LOCK_PX
local FRAME = 1 / 60
local ROW_W = 400
local ROW_H = 48
-- the tray buttons' font/size as a controller would publish them
local FONT = "BuilderSans"
local SIZE = 14

-- the natural width the engine will derive for a one-action tray, computed
-- the SAME way tests/row_actions.spec.luau's own localization test derives it
-- (the framework's own measurement oracle at the theme's own pad/floor) — so
-- the expectation is independent of this control's arithmetic.
local function expectedTrayWidth(label: string): number
	local metrics = themeSnapshot.neutral()
	local pad = themeSnapshot.resolveNumber(metrics, "controls.rowActions.buttonPad") or 0
	local minWidth = themeSnapshot.resolveNumber(metrics, "controls.rowActions.buttonMinWidth") or 0
	local measured = text_metrics.measure(label, FONT, SIZE, math.huge)
	return math.max(minWidth, measured.width + 2 * pad)
end

-- the `rectOf` the pointer handlers are handed. Every row_actions handler
-- ignores it past its own signature (it reads live rects through the
-- controller instead), same as the composeWithReorder tests' own stub.
local function rectOf(_path: string): any
	return nil
end

type World = any

local function hostedWorld(overrides: any?): World
	local core = LuauUI.newCore()
	local fired: { string } = {}
	local slides: { number } = {}
	-- boxed, because `onCommitHeight(nil)` ("no override, back to content
	-- height") is a real, load-bearing call this test asserts on
	local heights: { { px: number? } } = {}
	local textQueries: { string } = {}
	local clockTime = 0
	local clock = clockLib.new(core, {
		now = function()
			return clockTime
		end,
	})

	local spec: any = {
		id = "Row-1",
		trailing = {
			{
				id = "delete",
				label = "Delete",
				onAction = function()
					table.insert(fired, "delete")
				end,
			},
		},
		paths = { content = ROW, trayTrailing = TRAY_TRAILING },
		onSlide = function(px: number)
			table.insert(slides, px)
		end,
		onCommitHeight = function(px: number?)
			table.insert(heights, { px = px })
		end,
	}
	for key, value in overrides or {} do
		spec[key] = value
	end

	local engine = row_actions.buildHosted(LuauUI, core, spec)
	-- what a presenter hands a composite, handed over by the HOST instead —
	-- the two binds a hosted engine cannot get through a contribution of its
	-- own, because it has no node to attach one to.
	engine.bindMotion(clock, function()
		return clockTime
	end)
	engine.bindController({
		rectOf = function(path: string): any
			return if path == ROW then { x = 0, y = 0, w = ROW_W, h = ROW_H } else nil
		end,
		screenRectOf = function(path: string): any
			return if path == ROW then { x = 0, y = 0, w = ROW_W, h = ROW_H } else nil
		end,
		textAt = function(path: string): any
			table.insert(textQueries, path)
			return { font = FONT, size = SIZE }
		end,
	})

	local w: any = {
		core = core,
		engine = engine,
		fired = fired,
		slides = slides,
		heights = heights,
		textQueries = textQueries,
	}
	function w.tick(dt: number)
		clockTime += dt
		clock:step(dt)
		engine.syncGeometry() -- the host's own per-frame sync pass
	end
	function w.settle(frames: number?)
		for _ = 1, frames or 120 do
			w.tick(FRAME)
		end
	end
	function w.down(x: number, y: number): boolean?
		return engine.pointerHandlers.onPointerDown(HIT, { x = x, y = y, pointerType = "mouse" }, rectOf)
	end
	function w.move(x: number, y: number)
		engine.pointerHandlers.onPointerMove(HIT, { x = x, y = y, pointerType = "mouse" }, rectOf)
	end
	function w.up(x: number, y: number)
		engine.pointerHandlers.onPointerUp(HIT, { x = x, y = y, pointerType = "mouse" }, rectOf)
	end
	function w.lastSlide(): number?
		return w.slides[#w.slides]
	end
	return w
end

describe("RowActions hosted mode (Task 2): buildHosted — the engine with no blueprint", function()
	it("mounts NOTHING: the hosted engine carries no blueprint at all", function()
		local w = hostedWorld()
		expect(w.engine.blueprint).toBeNil()
		-- and it still answers the whole engine surface the host consumes
		expect(type(w.engine.pointerHandlers.onPointerDown)).toBe("function")
		expect(type(w.engine.open)).toBe("function")
		expect(type(w.engine.close)).toBe("function")
		expect(type(w.engine._open)).toBe("function")
		expect(type(w.engine._isOpen)).toBe("function")
		expect(type(w.engine._commitFirst)).toBe("function")
		expect(type(w.engine.dump)).toBe("function")
		expect(type(w.engine.dispose)).toBe("function")
		expect(w.engine.trayState).never().toBeNil()
	end)

	it("(a) a horizontal drag past the axis lock slides monotonically and reveals the trailing tray", function()
		local w = hostedWorld()
		w.tick(FRAME) -- one host frame: the tray naturals measure
		expect(w.down(200, 20)).toBe(true)
		w.tick(FRAME)
		-- INSIDE the lock radius: the axis is still unresolved, so nothing slides
		w.move(196, 20)
		expect(#w.slides).toBe(0)
		expect(w.engine.trayState:get()).toBeNil()
		w.tick(FRAME)
		w.move(200 - LOCK - 2, 20) -- crosses the lock, horizontal
		w.tick(FRAME)
		w.move(160, 20)
		w.tick(FRAME)
		w.move(120, 20)
		expect(#w.slides).toBe(3)
		expect(w.slides[1]).toBe(-(LOCK + 2))
		expect(w.slides[2]).toBe(-40)
		expect(w.slides[3]).toBe(-80)
		-- monotonic: every sample strictly further left than the one before it
		for i = 2, #w.slides do
			expect(w.slides[i]).toBeLessThan(w.slides[i - 1])
		end
		local tray = w.engine.trayState:get()
		expect(tray).never().toBeNil()
		expect(tray.edge).toBe("trailing")
		expect(#tray.actions).toBe(1)
		expect(tray.actions[1].id).toBe("delete")
		expect(tray.revealPx:get()).toBe(80)
	end)

	it("(b) releasing past the open threshold leaves the row open at the tray width", function()
		local w = hostedWorld()
		w.tick(FRAME)
		w.down(200, 20)
		w.tick(FRAME)
		w.move(200 - LOCK - 2, 20)
		w.tick(FRAME)
		w.move(120, 20) -- -80: past open (half a 64+ tray), far under commit (60% of 400)
		w.tick(FRAME)
		w.up(120, 20)
		w.settle()
		local tray = expectedTrayWidth("Delete")
		expect(w.engine._isOpen()).toBe(true)
		expect(w.engine.dump().openEdge).toBe("trailing")
		expect(w.engine.dump().offset).toBeCloseTo(-tray, 0.01)
		expect(w.lastSlide()).toBeCloseTo(-tray, 0.01)
		expect(#w.fired).toBe(0)
		-- the naturals were measured at the HOST's tray path, not at any path
		-- this control invented for itself (the `pathsOf` indirection)
		local askedHostPath = false
		for _, path in w.textQueries do
			if path == TRAY_TRAILING .. "/Action:delete" then
				askedHostPath = true
			end
		end
		expect(askedHostPath).toBe(true)
	end)

	it("(c) a full swipe past the commit threshold fires the first trailing action exactly once", function()
		-- DESTRUCTIVE: the full slide-off + collapse ladder (a non-destructive
		-- full swipe fires and springs straight back — covered by the standalone
		-- suite; what is new here is the host driving the collapse height)
		local fired: { string } = {}
		local w = hostedWorld({
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
		w.tick(FRAME)
		w.down(380, 20)
		w.tick(FRAME)
		w.move(380 - LOCK - 2, 20)
		w.tick(FRAME)
		w.move(80, 20) -- -300: past 60% of the 400px row
		w.tick(FRAME)
		w.up(80, 20)
		w.settle(240)
		expect(#fired).toBe(1)
		expect(w.engine.dump().phase).toBe("closed")
		expect(w.engine._isOpen()).toBe(false)
		-- the host drove the collapse: seeded at the row's live height, and
		-- released back to "no override" once the commit completed
		expect(#w.heights).toBeGreaterThan(1)
		expect(w.heights[1].px).toBe(ROW_H)
		expect(w.heights[#w.heights].px).toBeNil()
	end)

	it("(d) close() slides back to 0 and clears trayState", function()
		local w = hostedWorld()
		w.tick(FRAME)
		w.engine._open("trailing")
		w.settle()
		expect(w.engine._isOpen()).toBe(true)
		expect(w.engine.trayState:get()).never().toBeNil()
		w.engine.close()
		w.settle()
		expect(w.engine._isOpen()).toBe(false)
		expect(w.lastSlide()).toBe(0)
		expect(w.engine.dump().offset).toBe(0)
		expect(w.engine.trayState:get()).toBeNil()
	end)

	it("(e) two hosted engines share one coordinator: opening B closes A", function()
		local core = LuauUI.newCore()
		local coordinator = row_actions.newCoordinator(core)
		local function engineFor(id: string, contentPath: string)
			return row_actions.buildHosted(LuauUI, core, {
				id = id,
				coordinator = coordinator,
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
				paths = { content = contentPath, trayTrailing = contentPath .. "/Tray" },
				onSlide = function() end,
			})
		end
		local a = engineFor("Row-1", "/S/List/Canvas/Row-1")
		local b = engineFor("Row-2", "/S/List/Canvas/Row-2")
		a._open("trailing")
		expect(a._isOpen()).toBe(true)
		expect(b._isOpen()).toBe(false)
		b._open("trailing")
		expect(b._isOpen()).toBe(true)
		expect(a._isOpen()).toBe(false) -- one-open policy, through the SAME coordinator
		a.dispose()
		b.dispose()
	end)

	it("(f) a vertical drag never slides (axis lock: scrolling wins an ambiguous gesture)", function()
		local w = hostedWorld()
		w.tick(FRAME)
		expect(w.down(200, 20)).toBe(true)
		w.tick(FRAME)
		w.move(202, 20 + LOCK + 6) -- |dy| > |dx|, past the lock: vertical
		w.tick(FRAME)
		w.move(203, 20 + LOCK + 40) -- and it stays inert for the rest of the gesture
		w.tick(FRAME)
		w.up(203, 20 + LOCK + 40)
		w.settle(30)
		expect(#w.slides).toBe(0)
		expect(w.engine.trayState:get()).toBeNil()
		expect(w.engine._isOpen()).toBe(false)
	end)

	it("refuses the spec keys a hosted row cannot have (closed spec, constitution §4)", function()
		local core = LuauUI.newCore()
		local function build(extra: any)
			local spec: any = {
				id = "Row-1",
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
				paths = { content = ROW, trayTrailing = TRAY_TRAILING },
				onSlide = function() end,
			}
			for key, value in extra do
				spec[key] = value
			end
			return function()
				row_actions.buildHosted(LuauUI, core, spec)
			end
		end
		-- `content` is the HOST's, not this engine's: there is no blueprint here
		-- to wrap it in
		expect(build({ content = LuauUI.UI.Text({ id = "Body", text = "x" }) })).toThrow()
		expect(build({ width = { type = "fill", weight = 1 } })).toThrow()
		expect(build({ externalGesture = true })).toThrow()
		expect(build({ nonsense = true })).toThrow()
	end)

	it("requires `paths.content` and `onSlide` — the two things only the host can supply", function()
		local core = LuauUI.newCore()
		expect(function()
			row_actions.buildHosted(LuauUI, core, {
				id = "Row-1",
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
				onSlide = function() end,
			})
		end).toThrow()
		expect(function()
			row_actions.buildHosted(LuauUI, core, {
				id = "Row-1",
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
				paths = { content = ROW },
			})
		end).toThrow()
	end)

	it("a leading tray reveals from the other edge through the same engine", function()
		local w = hostedWorld({
			leading = { { id = "flag", label = "Flag", onAction = function() end } },
			trailing = nil,
			paths = { content = ROW, trayLeading = TRAY_LEADING },
		})
		w.tick(FRAME)
		w.down(100, 20)
		w.tick(FRAME)
		w.move(100 + LOCK + 2, 20)
		w.tick(FRAME)
		w.move(180, 20) -- +80
		local tray = w.engine.trayState:get()
		expect(tray).never().toBeNil()
		expect(tray.edge).toBe("leading")
		expect(tray.actions[1].id).toBe("flag")
		expect(tray.revealPx:get()).toBe(80)
		w.tick(FRAME)
		w.up(180, 20)
		w.settle()
		expect(w.engine._isOpen()).toBe(true)
		expect(w.engine.dump().openEdge).toBe("leading")
		expect(w.engine.dump().offset).toBeCloseTo(expectedTrayWidth("Flag"), 0.01)
	end)
end)
