--!strict

local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"
local ownedFrame = require "../ownership/frame"

export type Pump = {
	update: (pending: boolean) -> (),
}

local function create(owner: Owner.Owner, host: Host.Host, tick: Types.Value<number>, primitive: string): Pump
	local pump = ownedFrame(owner, function(body)
		local frames = host.frames
		if frames == nil then
			return Diagnostics.raise(
				"collection/no-frames",
				primitive .. " has pending admission work but its host has no frames",
				{
					primitive = primitive,
					contract = "admission over time requires host.frames.onFrame",
					fix = "implement host.frames or remove the admission budget",
				}
			)
		end
		return (frames).onFrame(body)
	end, function()
		tick:update(function(value)
			return value + 1
		end)
	end)
	return {
		update = function(pending: boolean)
			if pending then
				pump.start()
			else
				pump.stop()
			end
		end,
	}
end

return create
