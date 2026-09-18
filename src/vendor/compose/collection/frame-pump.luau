--!strict

local Diagnostics = require "../diagnostics"
local Host = require "../host"
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"

export type Pump = {
	update: (pending: boolean) -> (),
}

local function create(owner: Owner.Owner, host: Host.Host, tick: Types.Cell<number>, primitive: string): Pump
	local unsubscribe: (() -> ())? = nil

	local function stop()
		if unsubscribe ~= nil then
			unsubscribe()
			unsubscribe = nil
		end
	end

	local function start()
		if unsubscribe ~= nil then
			return
		end
		local frames = host.frames
		if frames == nil then
			Diagnostics.raise(
				"collection/no-frames",
				primitive .. " has pending admission work but its host has no frames",
				{
					primitive = primitive,
					contract = "admission over time requires host.frames.onFrame",
					fix = "implement host.frames or remove the admission budget",
				}
			)
		end
		unsubscribe = (frames :: Host.Frames).onFrame(function()
			tick:update(function(value)
				return value + 1
			end)
		end)
	end

	owner.own(stop)
	return {
		update = function(pending: boolean)
			if pending then
				start()
			else
				stop()
			end
		end,
	}
end

return create
