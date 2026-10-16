--!strict

local Host = require "../host"
local Owner = require "./owner"

export type Pump = { start: () -> (), stop: () -> () }

return function(owner: Owner.Owner, subscribe: ((number) -> ()) -> Host.Unsubscribe, body: (number) -> ()): Pump
	local unsubscribe: Host.Unsubscribe? = nil
	local function stop()
		local release = unsubscribe
		unsubscribe = nil
		if release then
			release()
		end
	end
	owner.own(stop)
	return {
		start = function()
			if unsubscribe == nil and not owner.isDisposed() then
				unsubscribe = subscribe(body)
			end
		end,
		stop = stop,
	}
end
