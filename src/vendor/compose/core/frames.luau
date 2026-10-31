--!strict

local Host = require "./host"
local Owner = require "./ownership/owner"
local Reactor = require "./reactive/reactor"

local function share(frames: Host.Frames, reactor: Reactor.Reactor): Host.Frames
	local listeners: { { live: boolean, body: (number) -> () } } = {}
	local stop: Host.Unsubscribe? = nil
	local dispatching = false
	local stale = 0
	local function compact()
		if dispatching or stale == 0 then
			return
		end
		stale = 0
		local write = 0
		for _, entry in listeners do
			if entry.live then
				write += 1
				listeners[write] = entry
			end
		end
		for index = #listeners, write + 1, -1 do
			listeners[index] = nil
		end
		if write == 0 and stop then
			local release = stop
			stop = nil
			release()
		end
	end
	local frameDelta = 0
	local position = 0
	local limit = 0
	local failures: { unknown }? = nil
	local function sweep()
		local delta = frameDelta
		while position < limit do
			position += 1
			local current = listeners[position]
			if current.live then
				current.body(delta)
			end
		end
	end
	local function dispatch()
		position = 0
		limit = #listeners
		while true do
			local ran, problem: unknown = pcall(sweep)
			if ran then
				break
			end
			local collected = failures or {}
			failures = collected
			table.insert(collected, problem)
		end
	end
	local function batched()
		Reactor.batch(reactor, dispatch)
	end
	return {
		now = frames.now,
		onFrame = function(body: (number) -> ()): Host.Unsubscribe
			local entry = { live = true, body = body }
			table.insert(listeners, entry)
			if stop == nil then
				stop = frames.onFrame(function(delta)
					local outerDelta, outerPosition, outerLimit, outerFailures = frameDelta, position, limit, failures
					dispatching = true
					failures = nil
					frameDelta = delta
					local ok, failure: unknown = pcall(batched)
					dispatching = false
					compact()
					local collected = failures or {}
					frameDelta, position, limit, failures = outerDelta, outerPosition, outerLimit, outerFailures
					if not ok then
						table.insert(collected, failure)
					end
					Owner.raiseAll(collected)
				end)
			end
			return function()
				if entry.live then
					entry.live = false
					stale += 1
				end
				compact()
			end
		end,
	}
end

return share
