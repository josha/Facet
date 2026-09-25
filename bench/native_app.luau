--!strict
local Facet = require("../src")
local engineLib = require("../tests/lib/native_engine")

return function(options: any?)
	local opts = options or {}
	local engine = engineLib.new({ recordCreated = false, cacheDefaults = true })
	local elapsed = 0
	engine.clock = function()
		return elapsed
	end
	local runtime = Facet.Roblox.createRuntime(engine)
	local target = engine.new("Folder")
	local root = Facet.Compose.createRootOwner(function()
		runtime.adopt(target)
	end, runtime.reactor)
	return {
		Facet = Facet,
		Compose = Facet.Compose,
		runtime = runtime,
		Host = runtime.constructors,
		UI = Facet.controls(runtime, { types = engine.types }),
		engine = engine,
		target = target,
		types = engine.types,
		viewport = opts.viewport or { w = 800, h = 600 },
		frame = function(dt: number?)
			elapsed += dt or 1 / 60
			engine.heartbeat.fire(dt or 1 / 60)
		end,
		dispose = function()
			root.dispose()
			runtime:dispose()
			assert(#target:GetChildren() == 0, "benchmark leaked mounted nodes")
		end,
	}
end
