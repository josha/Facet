--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")
local reducedMotion = require("./motion").reduced

return function(
	ctx: Types.Context,
	sample: () -> (string, boolean),
	restart: ((ComposeTypes.Use) -> string)?
): ComposeTypes.Readable<boolean>
	local Compose = ctx.Compose
	local frames = ctx.runtime.host.frames
	local reduce = reducedMotion(ctx)
	local limit = ctx.metric("motion.restLimit")
	local rested = Compose.cell(false)
	local stop: (() -> ())? = nil
	local function halt()
		local current = stop
		stop = nil
		if current then
			current()
		end
	end
	local function track()
		halt()
		if frames == nil or reduce() then
			rested:set(true)
			return
		end
		rested:set(false)
		local last: string? = nil
		local waited = 0
		local mine: (() -> ())? = nil
		mine = frames.onFrame(function(delta: number)
			if stop ~= mine then
				return
			end
			waited += delta
			local now, filled = sample()
			if reduce() or (now == last and filled) or waited > limit then
				halt()
				rested:set(true)
			end
			last = now
		end)
		stop = mine
	end
	if restart then
		local seen: string? = nil
		Compose.watch(function(use: ComposeTypes.Use)
			local key = restart(use)
			if key ~= seen then
				seen = key
				track()
			end
		end)
	else
		track()
	end
	Compose.cleanup(halt)
	return rested
end
