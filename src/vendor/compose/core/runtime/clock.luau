--!strict

local Host = require "../host"
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"
local Graph = require "../reactive/graph"
local Cell = require "../reactive/cell"
local ownedFrame = require "../ownership/frame"

export type Options = { duration: number?, deadline: number?, start: number?, interval: number? }

return function(host: Host.Host, ownerOf: (string) -> Owner.Owner)
	return function(options: Options?): Types.Readable<number>
		local owner = ownerOf "clock"
		local frames = assert(host.frames, "Compose clock requires host.frames")
		local settings: Options = options or {}
		local duration, deadline = settings.duration, settings.deadline
		local start = settings.start
		local interval = settings.interval or 0
		assert(duration == nil or deadline == nil, "Compose clock accepts duration or deadline")
		assert(
			start == nil or (duration == nil and deadline == nil and start == start and math.abs(start) < math.huge),
			"Compose clock start must be finite and exclusive of duration and deadline"
		)
		assert(interval >= 0 and interval < math.huge, "Compose clock interval must be finite and nonnegative")
		assert(
			duration == nil or (duration >= 0 and duration < math.huge),
			"Compose clock duration must be finite and nonnegative"
		)
		assert(
			deadline == nil or (deadline == deadline and math.abs(deadline) < math.huge),
			"Compose clock deadline must be finite"
		)
		local elapsed, pending = 0, 0
		local function read(): number
			return if start
				then math.max(0, frames.now() - start)
				elseif deadline then math.max(0, deadline - frames.now())
				elseif duration then math.max(0, duration - elapsed)
				else elapsed
		end
		local value = Cell.cell(read())
		local producer = (value :: unknown) :: Graph.Producer
		local function finished(current: number): boolean
			return (duration ~= nil or deadline ~= nil) and current == 0
		end
		local pump: ownedFrame.Pump
		pump = ownedFrame(owner, frames.onFrame, function(delta)
			elapsed += delta
			pending += delta
			local current = read()
			local done = finished(current)
			if pending >= interval or done then
				pending = if interval > 0 then pending % interval else 0
				value:set(current)
			end
			if done then
				pump.stop()
			end
		end)
		Graph.observations[producer] = function(observed)
			pump.stop()
			if observed and not owner.isDisposed() then
				value:set(read())
				if not finished(value:peek()) then
					pump.start()
				end
			end
		end
		owner.own(function()
			Graph.observations[producer] = nil
		end)
		return value
	end
end
