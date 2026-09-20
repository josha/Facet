--!strict
-- Native application fixture; the production host still drives both frame halves.
local Facet = require("../../src")
local fake = require("./fake_target")
local world = require("./world")
return function(viewport, metrics)
	local adapter, frame = fake.new(), nil
	adapter.scrollBarThickness = fake.SCROLL_BAR_RESERVE
	local app = Facet.new({
		newAdapter = function()
			return adapter
		end,
		newInputSystem = function(core)
			return Facet.newActionSystem(core)
		end,
		bindEnv = function(env)
			env:set("viewportRect", viewport)
			env:set("reducedMotion", true)
			if metrics then
				env:set("themeMetrics", metrics)
			end
			return function() end
		end,
		connectFrame = function(fn)
			frame = fn
			return function() end
		end,
	})
	world.own(app, adapter)
	return app, adapter, function(count)
		for _ = 1, count or 3 do
			frame(1 / 60)
		end
	end
end
