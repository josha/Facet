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

local Facet = require("../src") :: any
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
-- ...and the edit-mode minus the host parents when it wires `editing` (stage 1
-- of the Table-hosting order — see the describe block at the bottom of this
-- file). Same convention as the tray paths: the host names the node the engine's
-- own `UI.When` view actually mounts at, `{parent}/EditAffordanceWhen/then/
-- EditAffordance`, because that is the path an Activate arrives on.
local EDIT_AFFORDANCE = "/S/List/Canvas/RowActionsEdit/EditAffordanceWhen/then/EditAffordance"

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

-- ...and the distance the ROW travels to uncover that one-action band: the plate
-- plus the theme's own row-facing `rowGutter`, the negative space the band keeps
-- between itself and the row (device bug round 2026-08-12, finding A1a). Same
-- rule the `trayGap` fix already established — the tray uncovered has to be the
-- tray drawn.
local function expectedTravel(label: string): number
	local gutter = themeSnapshot.resolveNumber(themeSnapshot.neutral(), "controls.rowActions.rowGutter") or 0
	return expectedTrayWidth(label) + gutter
end

-- the `rectOf` the pointer handlers are handed. Every row_actions handler
-- ignores it past its own signature (it reads live rects through the
-- controller instead), same as the composeWithReorder tests' own stub.
local function rectOf(_path: string): any
	return nil
end

-- fix round 1, finding 2's own test double: the minimal shape `ensureKeysContext`/
-- `syncKeysEnabled` (src/controls/row_actions.luau) actually calls —
-- `createContext({name, priority, sink}) -> ctx`, `ctx.createAction(name, kind)
-- -> action` (`.bind`/`.onPressed`, both no-ops here — only whether/when
-- `ctx.setEnabled` is called matters to this test), `ctx.setEnabled(bool)`,
-- `ctx.destroy()`. Every built context is recorded so a test can inspect the
-- ONE context this engine ever builds (`ensureKeysContext` is idempotent —
-- see its own comment) and read back its live enabled state.
local function fakeActionSystem(): any
	local contexts: { any } = {}
	local api: any = { contexts = contexts }
	function api.createContext(_opts: any): any
		local enabled = true
		local ctx: any = {}
		function ctx.createAction(_name: string, _kind: string): any
			local action: any = {}
			function action.bind(_opts: any) end
			function action.onPressed(_fn: () -> ()) end
			return action
		end
		function ctx.setEnabled(v: boolean)
			enabled = v
		end
		function ctx.isEnabled(): boolean
			return enabled
		end
		function ctx.destroy() end
		table.insert(contexts, ctx)
		return ctx
	end
	return api
end

type World = any

local function hostedWorld(overrides: any?): World
	local core = Facet.newCore()
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
	-- `overrides.__unset` — the leading-edge test (below) needs to CLEAR the
	-- base spec's default `trailing`/`paths.trayTrailing`, and `trailing = nil`
	-- in an override table literal cannot do that: Lua never stores a nil
	-- value, so `pairs(overrides)` never visits a key written as `= nil` in
	-- the literal — the merge loop below would never see it, and the base
	-- default would silently survive. Named keys to delete, applied AFTER the
	-- merge, sidesteps the footgun rather than relying on a value Lua cannot
	-- represent.
	local unset: { string }? = if overrides ~= nil then (overrides :: any).__unset else nil
	--[[ THE TWO EDIT-MODE KNOBS (stage 1). Both are `__`-prefixed for the same
		reason `__unset` is: they are instructions to this builder, not spec keys,
		and the merge loop below skips every one of them. They exist so an edit-mode
		case reuses the base spec's OWN action — the one already wired into this
		world's `fired` — rather than declaring a second copy whose callback would
		have to be threaded back in by hand.

		`__destructive` promotes that action to `role = "destructive"`, which is one
		of the two halves the minus needs; `__editing` wires the other half (a live
		signal, exposed as `w.editing`) and names the path the host mounts the minus
		at, unless the case declared its own `paths`. ]]
	local wantsEditing = if overrides ~= nil then (overrides :: any).__editing == true else false
	if overrides ~= nil and (overrides :: any).__destructive == true then
		spec.trailing[1].role = "destructive"
	end
	for key, value in overrides or {} do
		if key ~= "__unset" and key ~= "__editing" and key ~= "__destructive" then
			spec[key] = value
		end
	end
	for _, key in unset or {} do
		spec[key] = nil
	end
	local editing: any = nil
	if wantsEditing then
		editing = core:signal(false)
		spec.editing = editing
		if spec.paths.editAffordance == nil then
			spec.paths.editAffordance = EDIT_AFFORDANCE
		end
	end

	local engine = row_actions.buildHosted(Facet, core, spec)
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
		editing = editing, -- nil unless the case asked for `__editing`
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
		local tray = expectedTravel("Delete")
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
		local core = Facet.newCore()
		local coordinator = row_actions.newCoordinator(core)
		local function engineFor(id: string, contentPath: string)
			return row_actions.buildHosted(Facet, core, {
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
		local core = Facet.newCore()
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
				row_actions.buildHosted(Facet, core, spec)
			end
		end
		-- `content` is the HOST's, not this engine's: there is no blueprint here
		-- to wrap it in
		expect(build({ content = Facet.UI.Text({ id = "Body", text = "x" }) })).toThrow()
		expect(build({ width = { type = "fill", weight = 1 } })).toThrow()
		expect(build({ externalGesture = true })).toThrow()
		expect(build({ nonsense = true })).toThrow()
	end)

	it("requires `paths.content` and `onSlide` — the two things only the host can supply", function()
		local core = Facet.newCore()
		expect(function()
			row_actions.buildHosted(Facet, core, {
				id = "Row-1",
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
				onSlide = function() end,
			})
		end).toThrow()
		expect(function()
			row_actions.buildHosted(Facet, core, {
				id = "Row-1",
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
				paths = { content = ROW },
			})
		end).toThrow()
	end)

	it("a leading tray reveals from the other edge through the same engine", function()
		local w = hostedWorld({
			leading = { { id = "flag", label = "Flag", onAction = function() end } },
			paths = { content = ROW, trayLeading = TRAY_LEADING },
			__unset = { "trailing" }, -- see `hostedWorld`'s own comment: `= nil` cannot clear a default
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
		expect(w.engine.dump().offset).toBeCloseTo(expectedTravel("Flag"), 0.01)
	end)

	-- ===== fix round 1 (review findings) ====================================

	it("(finding 1) refuses trailing actions with no paths.trayTrailing, by name", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			row_actions.buildHosted(Facet, core, {
				id = "Row-1",
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
				paths = { content = ROW }, -- no trayTrailing
				onSlide = function() end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(err, "paths.trayTrailing", 1, true)).never().toBeNil()
	end)

	it("(finding 1) refuses leading actions with no paths.trayLeading, by name", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			row_actions.buildHosted(Facet, core, {
				id = "Row-1",
				leading = { { id = "flag", label = "Flag", onAction = function() end } },
				paths = { content = ROW }, -- no trayLeading
				onSlide = function() end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(err, "paths.trayLeading", 1, true)).never().toBeNil()
	end)

	it("(finding 2) a focused hosted tray button counts as inside the row, keeping the keys context enabled", function()
		local w = hostedWorld()
		w.tick(FRAME)
		local actionSystem = fakeActionSystem()
		local focused = w.core:signal(nil :: string?)
		-- bound in the same order a presenter's own contribution walk binds
		-- them (contribution.luau) — neither bind alone builds the context;
		-- both fire `syncKeysEnabled`, still false (focus is nowhere yet).
		w.engine.bindActionSystem(actionSystem)
		w.engine.bindFocusGraph({ focused = focused })
		expect(#actionSystem.contexts).toBe(0) -- never built for a row nobody has focused (Task 11b)
		-- focus lands on a TRAY BUTTON's path — the host's shared overlay,
		-- never a descendant of `paths.content` — not on the row itself.
		focused:set(TRAY_TRAILING .. "/Action:delete")
		expect(#actionSystem.contexts).toBe(1)
		local ctx = actionSystem.contexts[1]
		expect(ctx.isEnabled()).toBe(true)
		-- focus leaves the row entirely: the context goes back to disabled.
		focused:set("/S/List/Canvas/Row-2/Hit")
		expect(ctx.isEnabled()).toBe(false)
	end)

	it("(finding 3) forwards outsideDismiss — active tracks isOpen, dismiss is close, never consumed", function()
		local w = hostedWorld()
		w.tick(FRAME)
		expect(type(w.engine.outsideDismiss)).toBe("table")
		expect(w.engine.outsideDismiss.consume).toBe(false)
		expect(w.engine.outsideDismiss.dismiss).toBe(w.engine.close)
		expect(w.engine.outsideDismiss.active:get()).toBe(false)
		w.engine._open("trailing")
		w.settle()
		expect(w.engine.outsideDismiss.active:get()).toBe(true)
		w.engine.outsideDismiss.dismiss()
		w.settle()
		expect(w.engine._isOpen()).toBe(false)
		expect(w.engine.outsideDismiss.active:get()).toBe(false)
	end)

	it("(finding 4) an ordinary close with nothing to collapse sends no spurious onSlide/onCommitHeight", function()
		local w = hostedWorld()
		w.tick(FRAME)
		-- never opened: `offset` is already 0 and `rowHeightOverride` is
		-- already nil for this row's entire life, so close()'s own
		-- `resetToClosed` has nothing to actually change.
		w.engine.close()
		w.settle(5)
		expect(#w.slides).toBe(0)
		expect(#w.heights).toBe(0)
	end)

	it(
		"(finding 4) a real close still forwards the settle's own onSlide(0) — the gate is on VALUE, not on close()",
		function()
			local w = hostedWorld()
			w.tick(FRAME)
			w.engine._open("trailing")
			w.settle()
			expect(#w.slides).toBeGreaterThan(0)
			w.engine.close()
			w.settle()
			expect(w.lastSlide()).toBe(0) -- the real transition away from open is still forwarded
			expect(w.engine.dump().offset).toBe(0)
		end
	)

	it("(finding 5) labels a hosted action-spec error with the hosted entry point, not the standalone one", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			row_actions.buildHosted(Facet, core, {
				id = "Row-1",
				trailing = { { label = "Delete" } }, -- missing onAction
				paths = { content = ROW, trayTrailing = TRAY_TRAILING },
				onSlide = function() end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(err, "newRowActionsHosted", 1, true)).never().toBeNil()
		-- discriminates from a substring match: "newRowActions(" (with the
		-- opening paren) only ever appears in the STANDALONE label's own
		-- message shape (`Facet newRowActions('id')`), never inside
		-- "newRowActionsHosted('id')".
		expect(string.find(err, "newRowActions('", 1, true)).toBeNil()
	end)

	it("(finding 5) labels a hosted coordinator-type error with the hosted entry point too", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			row_actions.buildHosted(Facet, core, {
				id = "Row-1",
				coordinator = "not-a-table",
				trailing = { { id = "delete", label = "Delete", onAction = function() end } },
				paths = { content = ROW, trayTrailing = TRAY_TRAILING },
				onSlide = function() end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(err, "newRowActionsHosted", 1, true)).never().toBeNil()
	end)
end)

--[[ ===== STAGE 1 of the Table-hosting order: `editing` IN HOSTED MODE ========
	`docs/plans/table-hosted-row-actions-stage2.md` §"the order that would lift
	it", item 1. `editing` was refused from `HOSTED_KEYS` **by name** — "a
	statement about a blueprint this mode never builds" — which was true of
	`content`/`width`/`externalGesture` and NOT true of this one: the minus is
	one `UI.When` view, exactly the shape `trayViews` already hands a host to
	parent, and the gutter is one Readable the host declares as its own row
	content's left padding.

	Conflict 1 of that plan is the reason it has to exist before Table can host:
	Table is the only surface with an edit-mode minus, it ships, and it is
	gamepad-reachable through the `padMinusTable` showcase case *because* the
	VirtualList surface cannot do it. A hosted Table without this stage would
	delete that case.

	THE TWO SEAMS, and why they are the shapes they are:
	  * `editAffordanceView` — a blueprint, not a callback, mirroring
	    `trayViews`: one construction shared by both modes
	    (`row_actions_root.buildEditAffordance`), so the two cannot drift.
	  * `editGutterPx` — a Readable, not the `onContentOffset` CALLBACK the plan
	    sketched. The plan was written against an older shape: the gutter stopped
	    being an offset at the director's 2026-08-12 device round (finding 2) and
	    became Content's own left PADDING, which a host declares reactively on its
	    own node. A callback would fire on every theme swap with nothing for the
	    host to do but write a signal it was already handed. ]]
describe("RowActions hosted mode: `editing` (Table-hosting order, stage 1)", function()
	it("accepts `editing` — it is no longer refused from the hosted spec by name", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			row_actions.buildHosted(Facet, core, {
				id = "Row-1",
				trailing = { { id = "delete", label = "Delete", role = "destructive", onAction = function() end } },
				editing = core:signal(false),
				paths = { content = ROW, trayTrailing = TRAY_TRAILING, editAffordance = EDIT_AFFORDANCE },
				onSlide = function() end,
			})
		end)
		expect(ok).toBe(true)
		expect(err).toBeNil()
	end)

	it(
		"hands the host an edit-affordance VIEW and a gutter Readable, and nothing to a row without both halves",
		function()
			-- (a) `editing` never wired: byte-identical to every shipped hosted row —
			-- no view, no gutter node at all. This is the cost guarantee, not a
			-- convenience: the whole hosted design is "a closed row mounts NOTHING".
			local w = hostedWorld({ __destructive = true })
			expect(w.engine.editAffordanceView).toBeNil()
			expect(w.engine.editGutterPx).toBeNil()

			-- (b) `editing` wired, but no destructive action anywhere: still nothing.
			local wNoDestructive = hostedWorld({ __editing = true })
			expect(wNoDestructive.engine.editAffordanceView).toBeNil()
			expect(wNoDestructive.engine.editGutterPx).toBeNil()

			-- (c) both halves: the view exists, and it is a blueprint the host can
			-- parent — the SAME `trayViews` shape, not a callback.
			local w2 = hostedWorld({ __destructive = true, __editing = true })
			expect(w2.engine.editAffordanceView).never().toBeNil()
			expect(w2.engine.editGutterPx).never().toBeNil()
			-- the gutter is LIVE: zero while not editing, a real reserve while editing
			expect(w2.engine.editGutterPx:get()).toBe(0)
			w2.editing:set(true)
			expect(w2.engine.editGutterPx:get()).toBeGreaterThan(0)
			w2.editing:set(false)
			expect(w2.engine.editGutterPx:get()).toBe(0)
		end
	)

	--[[ THE ROUTE THE `padMinusTable` SHOWCASE CASE TAKES, on a hosted engine.
		A hosted engine has no node of its own for a presenter's contribution walk
		to find, so an Activate on the minus arrives at the HOST's contribution and
		is handed back through `_handleActivate` — exactly how a hosted tray button's
		Activate already gets home. It must reach the SAME funnel standalone reaches
		(`commitDestructive`), so the slide-off + height-collapse sequence and the
		C8a "nothing stands painted once the row is carried clear" fix cannot
		diverge by host. ]]
	it("routes an Activate on the host's declared minus path into commitDestructive", function()
		local w = hostedWorld({ __destructive = true, __editing = true })
		w.editing:set(true)
		w.tick(FRAME)
		expect(w.engine._handleActivate(EDIT_AFFORDANCE)).toBe(true)
		w.settle()
		expect(w.fired).toEqual({ "delete" })
		expect(w.engine._isOpen()).toBe(false)
		expect(w.engine.dump().phase).toBe("closed")
	end)

	it("does not answer an Activate on some OTHER path that merely ends in the same node ids", function()
		local w = hostedWorld({ __destructive = true, __editing = true })
		w.editing:set(true)
		w.tick(FRAME)
		-- a DIFFERENT row's minus in the same list: the host declared THIS row's
		-- path, and an engine that answered for a sibling would delete the wrong
		-- row. Anchored match, not a suffix.
		expect(w.engine._handleActivate("/S/List/Canvas/Row-2/EditAffordanceWhen/then/EditAffordance")).toBe(false)
		expect(w.fired).toEqual({})
	end)

	--[[ THE SAME REFUSAL SHAPE `paths.trayLeading`/`trayTrailing` ALREADY HAVE
		(fix round 1, finding 1). Without the path the minus mounts under the host
		and is then unreachable: every Activate on it falls through `_handleActivate`
		to `false`, the host forwards it nowhere, and a button that ANNOUNCES itself
		as "Delete" (it borrows the destructive action's own accessible label) does
		nothing at all. Refused by name, at build time, instead. ]]
	it("refuses a hosted row that can show the minus but named no path for it", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			row_actions.buildHosted(Facet, core, {
				id = "Row-1",
				trailing = { { id = "delete", label = "Delete", role = "destructive", onAction = function() end } },
				editing = core:signal(false),
				paths = { content = ROW, trayTrailing = TRAY_TRAILING },
				onSlide = function() end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(err, "newRowActionsHosted", 1, true)).never().toBeNil()
		expect(string.find(err, "paths.editAffordance", 1, true)).never().toBeNil()
	end)

	it("still refuses `editing` that is not a Readable, with the hosted label", function()
		local core = Facet.newCore()
		local ok, err = pcall(function()
			row_actions.buildHosted(Facet, core, {
				id = "Row-1",
				trailing = { { id = "delete", label = "Delete", role = "destructive", onAction = function() end } },
				editing = true :: any,
				paths = { content = ROW, trayTrailing = TRAY_TRAILING, editAffordance = EDIT_AFFORDANCE },
				onSlide = function() end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(err, "newRowActionsHosted", 1, true)).never().toBeNil()
		-- DISCRIMINATING, not just "the word editing appears": the closed-spec
		-- refusal this replaces ALSO said `unknown spec key 'editing'`, so a check
		-- on the word alone would have passed against the very code this stage
		-- removes. The type error names `Readable<boolean>`; the key refusal never
		-- did.
		expect(string.find(err, "Readable<boolean>", 1, true)).never().toBeNil()
		expect(string.find(err, "unknown spec key", 1, true)).toBeNil()
	end)

	--[[ THE GUTTER THE HOST IS HANDED IS THE ONE THE ROW ACTUALLY NEEDS, measured
		against the theme rather than against this control's own arithmetic. It is
		`editAffordance + rowGutter` — the disc's diameter PLUS the same row-facing
		negative space the tray band spends (device bug round 2026-08-12, finding
		A2: a strip exactly one diameter wide leaves the disc touching the row it is
		meant to sit outside of).

		This is the check that makes the seam load-bearing rather than merely
		present. A host that reserved the bare diameter, or handed the tray's own
		`rowGutter` twice, would still expose a non-nil Readable and a positive
		number — and every other case in this block would still pass. It also
		covers the LEADING edge, where `row_actions_trays.buildTray` offsets the
		band by this same signal so it sits outside the minus rather than under it:
		the tray views a host parents are the very same array standalone puts in its
		row root, so one number is right for both. ]]
	it("the gutter it hands the host is the theme's own editAffordance + rowGutter, on the leading edge too", function()
		local metrics = themeSnapshot.neutral()
		local expected = (themeSnapshot.resolveNumber(metrics, "controls.rowActions.editAffordance") or 0)
			+ (themeSnapshot.resolveNumber(metrics, "controls.rowActions.rowGutter") or 0)
		expect(expected).toBeGreaterThan(0) -- the oracle itself has to be real

		local w = hostedWorld({
			__unset = { "trailing" },
			leading = { { id = "delete", label = "Delete", role = "destructive", onAction = function() end } },
			paths = { content = ROW, trayLeading = TRAY_LEADING, editAffordance = EDIT_AFFORDANCE },
			__editing = true,
		})
		expect(#w.engine.trayViews).toBe(1)
		expect(w.engine.editGutterPx:get()).toBe(0)
		w.editing:set(true)
		expect(w.engine.editGutterPx:get()).toBe(expected)
	end)
end)
