--!strict
local ComposeTypes = require("../vendor/compose/core")
local Types = require("./types")

return function(
	ctx: Types.Context,
	sample: () -> (string, boolean, boolean?),
	restart: ((ComposeTypes.Use) -> string)?
): ComposeTypes.Readable<boolean>
	local Compose = ctx.Compose
	local frames: { onFrame: ((number) -> ()) -> () -> () }? = ctx.runtime.host.frames
	local render = ctx.config.services.RunService and ctx.config.services.RunService.PreRender
	if render then
		frames = {
			onFrame = function(callback: (number) -> ()): () -> ()
				local connection = render:Connect(callback)
				return function()
					connection:Disconnect()
				end
			end,
		}
	end
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
		if frames == nil then
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
			local now, filled, allowed = sample()
			waited = if allowed ~= false then waited + delta else 0
			if allowed ~= false and ((filled and now == last) or waited > limit) then
				halt()
				rested:set(true)
			end
			last = if allowed ~= false then now else nil
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
