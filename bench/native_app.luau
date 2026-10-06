--!strict

type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type RobloxTypes = typeof(require("@repo/tools/typecheck/aliases").RobloxTypes)
type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
local Facet = require("../src")
local engineLib = require("../tests/lib/native_engine")

export type State = {
	Facet: Facet.Facet,
	Compose: Facet.ComposeModule,
	runtime: Facet.Runtime,
	Host: RobloxHost,
	UI: Facet.Controls,
	engine: engineLib.Engine,
	target: any,
	types: RobloxTypes,
	viewport: { w: number, h: number },
	frame: (number?) -> (),
	dispose: () -> (),
	[string]: any,
}
return function(options: any?): State
	local opts = options or {}
	local engine = engineLib.new({ recordCreated = false })
	local elapsed = 0
	engine.clock = function()
		return elapsed
	end
	local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
	local target = engine.new("Folder")
	local root = Facet.Compose.createRootOwner(function()
		runtime.adopt(target)
	end, runtime.reactor)
	return {
		Facet = Facet,
		Compose = Facet.Compose,
		runtime = runtime,
		Host = (runtime.constructors :: unknown) :: RobloxHost,
		UI = Facet.controls(runtime, { types = engine.types }),
		engine = engine,
		target = target,
		types = engine.types,
		viewport = opts.viewport or { w = 800, h = 600 },
		frame = function(dt: number?)
			elapsed += dt or 1 / 60
			engine.heartbeat:Fire(dt or 1 / 60)
		end,
		dispose = function()
			root.dispose()
			runtime:dispose()
			assert(#target:GetChildren() == 0, "benchmark leaked mounted nodes")
		end,
	}
end
