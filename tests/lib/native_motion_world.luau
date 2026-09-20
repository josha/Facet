--!strict
local Facet = require("../../src")
local fake = require("./fake_target")
local world = require("./world")
return function()
	local adapter = fake.new()
	local now, tick, core = 0, nil, nil
	local app = Facet.new({
		now = function()
			return now
		end,
		newAdapter = function()
			return adapter
		end,
		newInputSystem = function(value)
			core = value
			return Facet.newActionSystem(value)
		end,
		bindEnv = function(env)
			env:set("viewportRect", { x = 0, y = 0, w = 640, h = 480 })
			return function() end
		end,
		connectFrame = function(callback)
			tick = callback
			return function() end
		end,
	})
	world.own(app, adapter)
	return app,
		adapter,
		function(seconds)
			for _ = 1, math.max(1, math.floor(seconds * 60 + 0.5)) do
				now += 1 / 60
				tick(1 / 60)
			end
		end,
		core
end
