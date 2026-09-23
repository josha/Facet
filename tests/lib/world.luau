--!strict
--[[ The headless world: one Facet application over a fake render target, with
	frames stepped by hand.

	`new` takes an options table and returns a record read by name: `app`, `UI`
	(`app.controls`), `Compose`, `core`, `env`, `adapter`, `system`, `pres`.

	The viewport is set before the first solve, so nothing measures against 1x1.
	Each world owns one adapter; adapters are never shared between presenters.

	`record(id)` answers the `{ blueprint, api, dump, dispose }` record a composite
	control built under that id, so a spec authors with `UI.X("Id")({...})` exactly
	as an application does and still reaches the control's api and dump. ]]

local Facet = require("../../src") :: any
local fake_target = require("./fake_target")
local overflow_guard = require("./overflow_guard")
local testkit = require("./testkit")
local cleanup = require("../../src/core/cleanup")

local world = {}
local caseWorlds = {}

function world.own(app: any, adapter: any)
	table.insert(caseWorlds, { app = app, adapter = adapter })
end

-- Surface close remains reusable within a case. The case itself owns the whole
-- application, including auxiliary surfaces and the environment registration.
testkit.afterEach(function()
	local pending = caseWorlds
	caseWorlds = {}
	local steps = {}
	for _, w in pending do
		table.insert(steps, w.app.dispose)
		table.insert(steps, function()
			if w.adapter.liveCount then
				assert(w.adapter.liveCount() == 0, "Facet world: native objects remain after application disposal")
			end
		end)
	end
	cleanup(steps)
end)

-- Every composite control module `app.controls` registers through `build`.
local CONTROL_MODULES = {
	"alert",
	"async_image",
	"button",
	"callout",
	"chip",
	"collapsible_view",
	"combo_box",
	"disclosure_group",
	"label",
	"shortcut_hint",
	"badge",
	"skeleton",
	"status_indicator",
	"avatar",
	"avatar_group",
	"level_picker",
	"menu",
	"navigation_stack",
	"page_view",
	"picker",
	"picker_menu",
	"popover",
	"dialog",
	"notice",
	"card",
	"pagination",
	"color_picker",
	"step_indicator",
	"vote",
	"snackbar",
	"progress_view",
	"radial_menu",
	"rating",
	"row_actions",
	"sheet",
	"slider",
	"split_button",
	"stepper",
	"tab_view",
	"table",
	"text_input",
	"toggle",
}

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
	-- extra `Facet.new` options (`now`, `keyboardNavigation`, `clock`)
	hostOpts: any?,
	-- swap the render target (the billboard target, a fault-injecting fake)
	newAdapter: (() -> any)?,
	-- arm the fake target's op log (T12, default off per ruling A-11). Ignored
	-- when `newAdapter` swaps the target for something else.
	ops: boolean?,
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
	app: any,
	UI: any,
	Compose: any,
	close: (() -> ())?,
	node: any,
	present: (component: () -> any, presentOpts: any?) -> any,
	presentModal: (component: () -> any, presentOpts: any?) -> (any, () -> ()),
	scoped: (body: () -> ...any) -> ...any,
	record: (id: string) -> any,
	records: (id: string) -> { any },
	press: (key: string) -> (),
	tick: (dt: number?) -> (),
	frame: (dt: number?) -> (),
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
	local adapter = if o.newAdapter then o.newAdapter() else fake_target.new({ ops = o.ops == true })
	local core, env, system
	local hostOpts = table.clone(o.hostOpts or {})
	hostOpts.newAdapter = function()
		return adapter
	end
	hostOpts.newInputSystem = function(value)
		core = value
		system = Facet.newActionSystem(value)
		return system
	end
	hostOpts.bindEnv = function(value)
		env = value
		-- The viewport precedes the first solve.
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
		return function() end
	end
	-- Motion reads a virtual clock that `tick` and `settle` advance, so animation
	-- progress follows stepped frames. A spec that passes `hostOpts.now` owns time.
	local elapsed = 0
	if hostOpts.now == nil then
		hostOpts.now = function()
			return elapsed
		end
	end
	-- Specs step frames by hand through `tick` and `settle`.
	hostOpts.connectFrame = function()
		return function() end
	end
	-- Composite builders are read when the application registers its controls, so
	-- wrapping them for the span of that call records what each one builds.
	local built: { [string]: { any } } = {}
	local restore: { () -> () } = {}
	for _, name in CONTROL_MODULES do
		local module = require("../../src/controls/" .. name) :: any
		local original = module.build
		module.build = function(library: any, controlCore: any, spec: any, ...)
			local result = original(library, controlCore, spec, ...)
			local id = if type(spec) == "table" then spec.id else nil
			if type(id) == "string" and type(result) == "table" then
				built[id] = built[id] or {}
				table.insert(built[id], result)
			end
			return result
		end
		table.insert(restore, function()
			module.build = original
		end)
	end
	local ok, app = pcall(Facet.new, hostOpts)
	for _, undo in restore do
		undo()
	end
	if not ok then
		error(app, 0)
	end
	local pres = app.presenter

	local w: any = {
		app = app,
		UI = app.controls,
		Compose = Facet.Compose,
		core = core,
		env = env,
		adapter = adapter,
		system = system,
		pres = pres,
	}
	world.own(app, adapter)

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
	-- `component` is a function that returns the screen's root node.
	function w.present(component: () -> any, presentOpts: any?): any
		assert(type(component) == "function", "world.present takes a component function that returns the screen node")
		local close, node, handle = app.mount(component, presentOpts)
		w.close, w.node, w.handle = close, node, handle
		pres.refresh()
		w.controller = handle.controller
		if guardLabel == nil and node ~= nil and type(node.id) == "string" then
			guardLabel = node.id
		end
		guard()
		return handle
	end

	-- A modal over the presented screen: answers its handle and its close.
	function w.presentModal(component: () -> any, presentOpts: any?): (any, () -> ())
		local close, _, handle = app.presentModal(component, presentOpts)
		pres.refresh()
		return handle, close
	end

	-- Runs `body` under a throwaway owner, for constructing outside a mount (spec
	-- validation cases). The owner, and everything built under it, is released.
	function w.scoped(body: () -> ...any): ...any
		local owner = Facet.Compose.createOwner(core.reactor)
		local results = table.pack(pcall(Facet.Compose.withOwner, owner, body))
		owner.dispose()
		if not results[1] then
			error(results[2], 0)
		end
		return table.unpack(results, 2, results.n)
	end

	-- The newest record built under `id`; `records` answers every one, oldest first.
	function w.records(id: string): { any }
		return built[id] or {}
	end
	function w.record(id: string): any
		local list = built[id]
		if list == nil then
			error(`world.record: no composite control was built with id '{id}'`, 2)
		end
		return list[#list]
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
		elapsed += dt or 1 / 60
		pres.tick(dt or 1 / 60)
	end

	-- One production frame of `dt`: clock, then solve. Compose motion reaches the
	-- adapter on the solve, so a spec sampling mid-flight values steps with this.
	function w.frame(dt: number?)
		w.tick(dt)
		pres.refresh()
	end

	--[[ N frames of clock and solve. The DEFAULT is deliberately absent from the
		twenty-six copies' point of view: they used 6, 8, 90 and 120 and each of
		those numbers is a claim about the thing being settled, so it stays at the
		call site. 1 is the floor, because `settle(0)` reads as "settle" and does
		nothing at all. ]]
	function w.settle(frames: number?)
		for _ = 1, math.max(frames or 1, 1) do
			elapsed += 1 / 60
			pres.tick(1 / 60)
			pres.refresh()
		end
		guard()
	end

	return w :: World
end

return world
