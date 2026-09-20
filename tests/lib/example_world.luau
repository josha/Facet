--!strict
--[[ A headless world for the gallery's examples and client modules: one
	`tests/lib/world` application plus the context an example builds against.

	`w.ctx` is what `example.build(ctx)` reads. `w.presenter` is the presenter
	service with `present` / `presentModal` taking a component function, so a spec
	presents `built.screen` and dismisses the handle it gets back. ]]
local scenario_ctx = require("./scenario_ctx")
local world = require("./world")

local example_world = {}

function example_world.new(opts: any?): any
	local o = table.clone(opts or {})
	if o.viewport == nil then
		o.viewport = { x = 0, y = 0, w = 800, h = 600 }
	end
	if o.overflowGuardOff == nil then
		o.overflowGuardOff = "example specs assert containment themselves"
	end
	local w: any = world.new(o)
	local pres = w.pres
	local function presentWith(mount: any)
		return function(component: any, options: any?)
			assert(type(component) == "function", "example_world: present takes a component function")
			local _, node, handle = mount(component, options)
			w.node = node
			return handle
		end
	end
	w.presenter = setmetatable({
		present = presentWith(w.app.mount),
		presentModal = presentWith(w.app.presentModal),
	}, { __index = pres })
	w.ctx = scenario_ctx.of(w, o.ctx)
	w.ctx.presenter = w.presenter
	return w
end

return example_world
