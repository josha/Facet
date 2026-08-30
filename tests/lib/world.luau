--!strict
--[[ THE HEADLESS WORLD (reuse audit REUSE-88/95/96/104; controller ruling R12).

	Core → environment → viewport → render target → action system → presenter. A
	spec needs all six before it can present anything, and 106 spec-local builders
	across 100 files each wrote them out. That is not the finding. THE FINDING IS
	THE TWO ORDERS:

	    local core, env, system, adapter, pres = world()    -- 12 files
	    local core, env, adapter, system, pres = world()    -- 16 files

	Positions three and four are swapped, the same five names are used on both
	sides, and Luau will bind an action system to a variable called `adapter`
	without a word. Ten of the twelve are byte-identical, so a spec author copying
	a line from a neighbouring file — which is exactly how a suite this size is
	written — has a coin-flip chance of silently testing something else. The bug
	does not fail loudly; it fails as "the adapter has no `node` method", three
	edits later, in a file nobody was changing.

	SO THIS CONSTRUCTOR IS KEYWORD-ONLY AND ITS RESULT IS NAMED. There is no
	tuple to get wrong in either direction. `new` takes an options TABLE (so
	adding an option can never shift an argument) and returns an object whose
	fields are read by name.

	SCOPE — R12, deliberately narrow. This substrate lands with the files that
	carry the two colliding orders migrated onto it and NOTHING ELSE. The other
	~78 spec-local builders are not churn worth taking: each is a few lines, each
	is read beside the spec that uses it, and rewriting a hundred files to prove a
	point is how a test suite acquires a regression nobody can bisect. THE
	FOLLOW-UP TRIGGER, recorded in artifacts/release-candidate-review/reuse-ledger.md:
	the next spec file that ADDS a builder migrates its file instead.

	THE TWO CONSTRUCTION INVARIANTS THIS MODULE OWNS, both of which are past
	defects in this repository rather than theory:

	  1. `viewportRect` is set BEFORE the presenter exists. A first solve against
	     an unset viewport runs at 1×1, and every measured thing in it is wrong in
	     a way the second frame silently repairs — the role-pick pop, 2026-08-04.
	  2. The presenter is constructed AFTER the adapter, and the adapter is never
	     shared between two presenters (the instance map and the
	     capture/cursor state are adapter-scoped).

	`tests/lib/large_text.luau`'s `world` is the prototype this is generalised
	from, and keeps its own because its options are the large-text matrix's
	(offset, theme, input class) rather than these.
]]

local Facet = require("../../src") :: any
local fake_target = require("./fake_target")
local overflow_guard = require("./overflow_guard")

local world = {}

export type Rect = { x: number, y: number, w: number, h: number }

export type Opts = {
	--[[ the viewport every solve is measured against. Default is a 390×844
		phone portrait — the most common shape in this suite, and the one the
		byte-identical builders all used. ]]
	viewport: Rect?,
	safeInsets: { top: number, bottom: number, left: number, right: number }?,
	capabilities: { [string]: boolean }?,
	preferredInput: string?,
	displaySize: string?,
	themeMetrics: any?,
	reducedMotion: boolean?,
	-- extra environment facts, applied last, so a spec can set anything the
	-- named options do not cover without a second constructor
	env: { [string]: any }?,
	-- forwarded verbatim to `Facet.newPresenter`'s fifth argument
	presenterOpts: any?,
	-- swap the render target (the billboard target, a fault-injecting fake)
	newAdapter: (() -> any)?,
	--[[ THE CONTAINMENT INVARIANT IS ON BY DEFAULT (overflow guard layer 1,
		2026-08-21). Every screen this world presents and settles is asked, at every
		settle, whether anything it paints is outside the box it lives in and
		whether any visible string solved to nothing — see
		`tests/lib/overflow_guard.luau` for the escape that commissioned it.

		A FIXTURE MAY TURN IT OFF ONLY BY SAYING WHY. The option is a STRING, not a
		boolean, and the string is the reason: a spec that deliberately builds an
		overflowing screen (that is the whole point of a diagnostics fixture) states
		that here, in the constructor, where the next reader of the file will see it.
		`false` is not accepted, because "off" with no reason is how an always-on
		check becomes a check nobody notices is off. ]]
	overflowGuardOff: string?,
	-- what the guard calls this world in its message; defaults to the presented
	-- screen's id, which is the right answer in every fixture that presents one
	overflowLabel: string?,
}

export type World = {
	core: any,
	env: any,
	adapter: any,
	system: any,
	pres: any,
	present: (screen: any, presentOpts: any?) -> any,
	press: (key: string) -> (),
	tick: (dt: number?) -> (),
	settle: (frames: number?) -> (),
	-- the containment invariant, callable on demand: a spec that drives a state
	-- WITHOUT settling (an activation that solves synchronously) still has to be
	-- able to ask
	overflowGuard: () -> (),
	handle: any,
	controller: any,
}

local DEFAULT_VIEWPORT: Rect = { x = 0, y = 0, w = 390, h = 844 }

function world.new(opts: Opts?): World
	local o: Opts = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)

	-- INVARIANT 1: before anything can solve (see the header)
	env:set("viewportRect", o.viewport or DEFAULT_VIEWPORT)
	if o.safeInsets ~= nil then
		env:set("coreSafeInsets", o.safeInsets)
	end
	if o.capabilities ~= nil then
		env:set("capabilities", o.capabilities)
	end
	if o.preferredInput ~= nil then
		env:set("preferredInput", o.preferredInput)
	end
	if o.displaySize ~= nil then
		env:set("displaySize", o.displaySize)
	end
	if o.themeMetrics ~= nil then
		env:set("themeMetrics", o.themeMetrics)
	end
	if o.reducedMotion ~= nil then
		env:set("reducedMotion", o.reducedMotion)
	end
	for key, value in o.env or {} do
		env:set(key, value)
	end

	-- INVARIANT 2: adapter first, one presenter per adapter
	local adapter = if o.newAdapter then o.newAdapter() else fake_target.new()
	local system = Facet.newActionSystem(core)
	local pres = Facet.newPresenter(core, env, adapter, system, o.presenterOpts)

	local w: any = { core = core, env = env, adapter = adapter, system = system, pres = pres }

	--[[ THE INVARIANT, AT EVERY POINT THIS WORLD HANDS CONTROL BACK. A check that
		ran only at mount would miss every defect a state change introduces, which is
		the class the escape belongs to; a check that ran inside `settle`'s frame loop
		would ask the same question 120 times and cost 120 times as much for one
		answer. So it runs once, after the loop, on the state the caller is about to
		assert against. ]]
	local guardLabel: string? = o.overflowLabel
	local function guard()
		if o.overflowGuardOff ~= nil then
			return
		end
		if adapter.paths == nil or adapter.node == nil then
			-- a fault-injecting or billboard target with no node census: nothing to
			-- read, and inventing an answer from a target that cannot answer is the
			-- "instrument reading an unreal surface" trap
			return
		end
		overflow_guard.assertContained(adapter, guardLabel)
	end
	w.overflowGuard = guard

	-- present + settle in one, because a presented screen that has not solved is
	-- a state no spec in this suite is ever interested in
	function w.present(screen: any, presentOpts: any?): any
		w.handle = pres.present(screen, presentOpts)
		pres.refresh()
		w.controller = w.handle.controller
		if guardLabel == nil and type(screen) == "table" then
			local props = (screen :: any).props
			guardLabel = if type(props) == "table" and type(props.id) == "string" then props.id else nil
		end
		guard()
		return w.handle
	end

	--[[ A KEY DOWN AND BACK UP, which is what seventeen copies of `press` did.
		Both edges, because a down with no up leaves the action system holding a
		key the next case then behaves oddly under — the single most common way a
		hand-rolled press helper goes wrong. ]]
	function w.press(key: string)
		system.deviceKey(key, true)
		system.deviceKey(key, false)
	end

	function w.tick(dt: number?)
		pres.tick(dt or 1 / 60)
	end

	--[[ N frames of clock and solve. The DEFAULT is deliberately absent from the
		twenty-six copies' point of view: they used 6, 8, 90 and 120 and each of
		those numbers is a claim about the thing being settled, so it stays at the
		call site. 1 is the floor, because `settle(0)` reads as "settle" and does
		nothing at all. ]]
	function w.settle(frames: number?)
		for _ = 1, math.max(frames or 1, 1) do
			pres.tick(1 / 60)
			pres.refresh()
		end
		guard()
	end

	return w :: World
end

return world
