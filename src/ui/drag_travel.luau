--!strict
local Types = require("./types")
local travelEngine = require("./travel_engine")
local reducedMotion = require("./motion").reduced

return function(ctx: Types.Context, parent: Instance, sample: (number) -> (), complete: () -> ()): () -> ()
	local stop = ctx.runtime.mount(function()
		travelEngine(ctx, {
			initial = { 0 },
			target = function()
				return { 1 }
			end,
			sample = function(values)
				sample(values[1])
			end,
			complete = complete,
			reduced = reducedMotion(ctx),
			motion = "ease",
			duration = ctx.metric("motion.durations.travel"),
			ease = ctx.motionEase("travel"),
			spring = ctx.motionSpring("travel"),
		})
		return ctx.Host.Folder { Name = "FacetDragTravel" }
	end, parent)
	return stop
end
