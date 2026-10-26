--!strict

local Host = require "../host"
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"
local Graph = require "../reactive/graph"
local NodeCast = require "../reactive/node"
local Cell = require "../reactive/cell"
local ownedFrame = require "../ownership/frame"

export type Options = { duration: number?, deadline: number?, start: number?, interval: number?, step: number? }

return function(host: Host.Host, ownerOf: (string) -> Owner.Owner)
	return function(options: Options?): Types.ReadOnlyValue<number>
		local owner = ownerOf "clock"
		local frames = assert(host.frames, "Compose clock requires host.frames")
		local settings: Options = options or {}
		local duration, deadline = settings.duration, settings.deadline
		local start = settings.start
		local interval = settings.interval or 0
		local step = settings.step
		assert(
			step == nil or (step > 0 and step < math.huge and interval == 0),
			"Compose clock step must be finite and positive, and exclusive of interval"
		)
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
		local producer = NodeCast.nodeOf(value)
		local function finished(current: number): boolean
			return (duration ~= nil or deadline ~= nil) and current == 0
		end
		local pump: ownedFrame.Pump
		pump = ownedFrame(owner, frames.onFrame, function(delta)
			elapsed += delta
			pending += delta
			local current = read()
			local done = finished(current)
			if step then
				if done or math.floor(current / step) ~= math.floor(value:peek() / step) then
					value:set(current)
				end
			elseif pending >= interval or done then
				pending = if interval > 0 then pending % interval else 0
				value:set(current)
			end
			if done then
				pump.stop()
			end
		end)
		Graph.observations[producer] = function(observed)
			pump.stop()
			if observed and not Owner.isDisposed(owner) then
				value:set(read())
				if not finished(value:peek()) then
					pump.start()
				end
			end
		end
		Owner.own(owner, function()
			Graph.observations[producer] = nil
		end)
		return value
	end
end
