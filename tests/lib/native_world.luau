--!strict
-- Native application fixture; the production host still drives both frame halves.
local Facet = require("../../src")
local fake = require("./fake_target")
local world = require("./world")
return function(viewport, metrics)
	local adapter, frame = fake.new(), nil
	adapter.scrollBarThickness = fake.SCROLL_BAR_RESERVE
	-- ...and the action system itself, returned FOURTH (additive — every existing
	-- caller takes three values and is unchanged). An `App` deliberately does not
	-- publish its input system, and a fixture that wants to press a KEY rather
	-- than call a focus verb needs one: the keys a control claims dynamically
	-- (the Adjust binding, live only while the ring is on a declared target) exist
	-- nowhere else, so testing them through `navigateDirection` would walk past
	-- the claim and prove a path no player can take.
	local system
	local app = Facet.new({
		newAdapter = function()
			return adapter
		end,
		newInputSystem = function(core)
			system = Facet.newActionSystem(core)
			return system
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
	end, system
end
