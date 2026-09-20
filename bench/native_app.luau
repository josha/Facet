--!strict
-- One headless Facet application over the fake render target. Frames are
-- stepped by hand: `frame(dt)` is the host frame (clock, hooks, then solve) and
-- `tick(dt)` is its clock half alone. Motion reads a virtual clock that both
-- advance, so animation progress follows the stepped frames.
local Facet = require("../src") :: any
local fake_target = require("../tests/lib/fake_target")

export type Opts = {
	viewport: { x: number, y: number, w: number, h: number }?,
	env: { [string]: any }?,
	-- writes further environment facts before the first solve
	configure: ((env: any) -> ())?,
	newAdapter: (() -> any)?,
	hostOpts: { [string]: any }?,
}

return function(opts: Opts?)
	local o: Opts = opts or {}
	local adapter = if o.newAdapter then o.newAdapter() else fake_target.new()
	local frame: (dt: number) -> ()
	local core, env, system
	local hostOpts: { [string]: any } = table.clone(o.hostOpts or {})
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
		if o.viewport then
			env:set("viewportRect", o.viewport)
		end
		for key, fact in o.env or {} do
			env:set(key, fact)
		end
		if o.configure then
			o.configure(env)
		end
		return function() end
	end
	local elapsed = 0
	if hostOpts.now == nil then
		hostOpts.now = function()
			return elapsed
		end
	end
	hostOpts.connectFrame = function(fn)
		frame = fn
		return function() end
	end
	local app = Facet.new(hostOpts)
	return {
		Facet = Facet,
		Compose = Facet.Compose,
		app = app,
		UI = app.controls,
		adapter = adapter,
		core = core,
		env = env,
		system = system,
		pres = app.presenter,
		frame = function(dt: number?)
			elapsed += dt or 1 / 60
			frame(dt or 1 / 60)
		end,
		tick = function(dt: number?)
			elapsed += dt or 1 / 60
			app.presenter.tick(dt or 1 / 60)
		end,
	}
end
