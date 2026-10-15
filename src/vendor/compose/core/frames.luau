--!strict

local Host = require "./host"
local Owner = require "./ownership/owner"
local Reactor = require "./reactive/reactor"

local function share(frames: Host.Frames, reactor: Reactor.Reactor): Host.Frames
	local listeners: { { live: boolean, body: (number) -> () } } = {}
	local stop: Host.Unsubscribe? = nil
	local dispatching = false
	local function compact()
		if dispatching then
			return
		end
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
	return {
		now = frames.now,
		onFrame = function(body: (number) -> ()): Host.Unsubscribe
			local entry = { live = true, body = body }
			table.insert(listeners, entry)
			if stop == nil then
				stop = frames.onFrame(function(delta)
					dispatching = true
					local failures: { unknown } = {}
					local ok, failure: unknown = pcall(function()
						reactor:batch(function()
							for index = 1, #listeners do
								local current = listeners[index]
								if current.live then
									local ran, problem: unknown = pcall(current.body, delta)
									if not ran then
										table.insert(failures, problem)
									end
								end
							end
						end)
					end)
					dispatching = false
					compact()
					if not ok then
						table.insert(failures, failure)
					end
					Owner.raiseAll(failures)
				end)
			end
			return function()
				entry.live = false
				compact()
			end
		end,
	}
end

return share
