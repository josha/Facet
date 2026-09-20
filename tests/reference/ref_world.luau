--!strict
--[[ One reference app mounted in a headless world.

	`new(proof, opts)` builds the app against a `tests/lib/world` application and
	mounts its screen component (an app that presents itself is left as built).
	The record carries the world's parts by the names the reference specs read:
	`core`, `env`, `adapter`, `presenter`, `system`, `app`, `built`, `handle`,
	plus `close()` and the world itself as `world`. ]]

local Facet = require("../../src") :: any
local fake_target = require("../lib/fake_target")
local world = require("../lib/world")

local refWorld = {}

export type Opts = {
	viewport: { x: number, y: number, w: number, h: number }?,
	-- environment facts, applied before the first solve
	facts: { [string]: any }?,
	keyboardNavigation: boolean?,
	-- the fake target reserves the live engine's scroll bar thickness
	scrollBar: boolean?,
	-- runs after the world exists and before the app is built
	before: ((env: any, adapter: any) -> ())?,
	-- the app's `deps`; `app` is added to whatever this answers
	deps: ((env: any, system: any, presenter: any, adapter: any, core: any) -> { [string]: any })?,
}

-- A world with no app in it yet.
function refWorld.open(opts: Opts?): any
	local o: Opts = opts or {}
	local w: any = world.new({
		viewport = o.viewport or { x = 0, y = 0, w = 1200, h = 800 },
		env = o.facts,
		hostOpts = if o.keyboardNavigation then { keyboardNavigation = true } else nil,
		newAdapter = if o.scrollBar
			then function()
				local adapter = fake_target.new();
				(adapter :: any).scrollBarThickness = fake_target.SCROLL_BAR_RESERVE
				return adapter
			end
			else nil,
		overflowGuardOff = "the reference sweeps own containment; these cases drive states the sweeps waive by name",
	})
	if o.before then
		o.before(w.env, w.adapter)
	end
	return w
end

-- Builds `proof` in `w` and mounts it unless it presented itself.
function refWorld.mount(w: any, proof: any, makeDeps: any?): any
	local deps: any = if makeDeps
		then makeDeps(w.env, w.system, w.pres, w.adapter, w.core)
		else { env = w.env, actionSystem = w.system, presenter = w.pres, adapter = w.adapter }
	deps.app = w.app
	local built = proof.build(Facet, w.core, deps)
	local handle = built.handle
	local close
	if handle == nil then
		handle = w.present(built.screen, built.present)
		close = w.close
	else
		w.pres.refresh()
		close = built.dispose
	end
	return {
		world = w,
		app = w.app,
		core = w.core,
		env = w.env,
		adapter = w.adapter,
		presenter = w.pres,
		system = w.system,
		built = built,
		handle = handle,
		close = close,
	}
end

--[[ The application a reference app builds against, assembled over a
	`tests/lib/harness` presenter for the specs that construct their world there.
	Methods are read off `presenter` at call time, so a spec that wraps
	`presenter.presentModal` still sees every surface the app opens. ]]
function refWorld.harnessApp(harness: any, core: any, env: any, presenter: any): any
	local controls, _, library = harness.libraryOf(core)
	local function present(method: string)
		return function(component: () -> any, options: any?)
			local handle = presenter[method](component, options)
			return function()
				presenter.dismiss(handle)
			end, nil, handle
		end
	end
	return {
		controls = controls,
		runtime = library.runtime,
		environment = env,
		presenter = presenter,
		onFrame = presenter.onTick,
		mount = present("present"),
		presentModal = present("presentModal"),
	}
end

function refWorld.new(proof: any, opts: Opts?): any
	return refWorld.mount(refWorld.open(opts), proof, if opts then opts.deps else nil)
end

return refWorld
